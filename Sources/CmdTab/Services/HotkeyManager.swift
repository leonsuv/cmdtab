import AppKit
import Carbon
import CoreGraphics
import Foundation

@MainActor
protocol HotkeyManagerDelegate: AnyObject {
    var isSwitcherVisible: Bool { get }
    var isSearchModeActive: Bool { get }
    func hotkeyDidTrigger(shortcut: ShortcutConfig, reverse: Bool)
    func hotkeyDidReleaseHoldModifiers()
    func hotkeyDidPressEscape()
    func hotkeyDidPressReturn()
    func hotkeyDidPressArrow(_ direction: NavigationDirection)
    func hotkeyDidPressActionKey(_ action: SwitcherKeyAction)
    func hotkeyDidPressQuickJump(_ number: Int)
    func hotkeyDidTypeSearchCharacter(_ char: String)
    func hotkeyDidPressBackspace()
}

enum NavigationDirection {
    case left, right, up, down
}

enum SwitcherKeyAction {
    case closeWindow
    case quitApp
    case minimizeWindow
    case hideApp
    case toggleFullscreen
    case togglePin
    case snapLeft
    case snapRight
    case snapMaximize
    case toggleSearch
}

@MainActor
final class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    weak var delegate: HotkeyManagerDelegate?

    /// Set to true while the user is recording a new shortcut in Settings
    var isPausedForRecording: Bool = false

    @Published private(set) var isRunning: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activeHoldModifiers: ModifierFlags?
    private var activeTriggerKeyCode: UInt16?
    private var activeShortcut: ShortcutConfig?

    private init() {}

    @discardableResult
    func start() -> Bool {
        stop()

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                return manager.handleEventFromTap(proxy: proxy, type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            isRunning = false
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isRunning = false
        clearActiveSession()
    }

    func clearActiveSession() {
        activeHoldModifiers = nil
        activeTriggerKeyCode = nil
        activeShortcut = nil
    }

    /// Runs on the main RunLoop (since we added the source to CFRunLoopGetMain).
    private func handleEventFromTap(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if isPausedForRecording {
            return Unmanaged.passUnretained(event)
        }

        let currentModifiers = ModifierFlags.from(cgFlags: event.flags)

        if type == .flagsChanged {
            if let holdMods = activeHoldModifiers,
               let delegate,
               delegate.isSwitcherVisible {
                // Check if all required hold modifiers are still pressed
                if !currentModifiers.isSuperset(of: holdMods) {
                    activeHoldModifiers = nil
                    activeTriggerKeyCode = nil
                    delegate.hotkeyDidReleaseHoldModifiers()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyUp {
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        // 1. If switcher is currently visible, handle navigation, actions, or search typing
        if let delegate, delegate.isSwitcherVisible {
            // Re-pressing the active trigger key cycles forward/backward
            if let activeShortcut, keyCode == activeShortcut.triggerKeyCode,
               let holdMods = activeHoldModifiers,
               currentModifiers.isSuperset(of: holdMods) {
                let reverse = currentModifiers.contains(.shift) && !holdMods.contains(.shift)
                delegate.hotkeyDidTrigger(shortcut: activeShortcut, reverse: reverse)
                return nil
            }

            if keyCode == UInt16(kVK_Escape) {
                clearActiveSession()
                delegate.hotkeyDidPressEscape()
                return nil
            }

            if keyCode == UInt16(kVK_Return) || keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                clearActiveSession()
                delegate.hotkeyDidPressReturn()
                return nil
            }

            switch Int(keyCode) {
            case kVK_LeftArrow:
                delegate.hotkeyDidPressArrow(.left)
                return nil
            case kVK_RightArrow:
                delegate.hotkeyDidPressArrow(.right)
                return nil
            case kVK_UpArrow:
                delegate.hotkeyDidPressArrow(.up)
                return nil
            case kVK_DownArrow:
                delegate.hotkeyDidPressArrow(.down)
                return nil
            case kVK_Tab:
                if let activeShortcut {
                    let reverse = currentModifiers.contains(.shift)
                    delegate.hotkeyDidTrigger(shortcut: activeShortcut, reverse: reverse)
                    return nil
                }
            default:
                break
            }

            // If search mode is active, route typing to search bar (unless Cmd modifier is held for actions)
            if delegate.isSearchModeActive {
                if keyCode == UInt16(kVK_Delete) {
                    delegate.hotkeyDidPressBackspace()
                    return nil
                }
                if currentModifiers.contains(.command) {
                    if let action = mapActionKey(keyCode: keyCode) {
                        delegate.hotkeyDidPressActionKey(action)
                        return nil
                    }
                }
                if let unicode = extractPrintableString(from: event), !unicode.isEmpty {
                    delegate.hotkeyDidTypeSearchCharacter(unicode)
                    return nil
                }
                return nil
            }

            // Not in search mode: check quick-jump numbers (1-9) & window action keys
            if let jumpNum = mapQuickJumpNumber(keyCode: keyCode) {
                clearActiveSession()
                delegate.hotkeyDidPressQuickJump(jumpNum)
                return nil
            }

            if keyCode == UInt16(kVK_ANSI_Slash) || keyCode == UInt16(kVK_Space) {
                delegate.hotkeyDidPressActionKey(.toggleSearch)
                return nil
            }

            if let action = mapActionKey(keyCode: keyCode) {
                delegate.hotkeyDidPressActionKey(action)
                return nil
            }

            return nil
        }

        // 2. Switcher is NOT visible: check if any configured shortcut matches!
        let shortcuts = AppSettings.shared.payload.shortcuts.filter(\.isEnabled)
        // Sort by most specific modifier count first (so Option+Shift+Tab matches before Option+Tab)
        let sortedShortcuts = shortcuts.sorted {
            $0.holdModifiers.rawValue.nonzeroBitCount > $1.holdModifiers.rawValue.nonzeroBitCount
        }

        for shortcut in sortedShortcuts {
            guard keyCode == shortcut.triggerKeyCode else { continue }
            guard !shortcut.holdModifiers.isEmpty else { continue }

            // Allow Shift as a reverse modifier if Shift is not part of the shortcut's holdModifiers
            var modsWithoutShift = currentModifiers
            let shiftUsedAsReverse = !shortcut.holdModifiers.contains(.shift) && currentModifiers.contains(.shift)
            if shiftUsedAsReverse {
                modsWithoutShift.remove(.shift)
            }

            if modsWithoutShift == shortcut.holdModifiers {
                if WindowManager.shared.shouldIgnoreShortcutsForFrontmostApp() {
                    return Unmanaged.passUnretained(event)
                }

                activeHoldModifiers = shortcut.holdModifiers
                activeTriggerKeyCode = shortcut.triggerKeyCode
                activeShortcut = shortcut
                delegate?.hotkeyDidTrigger(shortcut: shortcut, reverse: shiftUsedAsReverse)
                return nil // Consume event (blocks native macOS Cmd+Tab!)
            }
        }

        // 3. Check global Rectangle-style Window Snapping shortcuts
        let snapping = AppSettings.shared.payload.snapping
        if snapping.isEnabled && !currentModifiers.isEmpty {
            for (rawAction, combo) in snapping.shortcuts {
                guard combo.keyCode == keyCode,
                      combo.modifiers == currentModifiers,
                      let action = SnapAction(rawValue: rawAction) else {
                    continue
                }
                if WindowManager.shared.shouldIgnoreShortcutsForFrontmostApp() {
                    return Unmanaged.passUnretained(event)
                }
                WindowSnapManager.shared.execute(action)
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func mapActionKey(keyCode: UInt16) -> SwitcherKeyAction? {
        switch Int(keyCode) {
        case kVK_ANSI_W: return .closeWindow
        case kVK_ANSI_Q: return .quitApp
        case kVK_ANSI_M: return .minimizeWindow
        case kVK_ANSI_H: return .hideApp
        case kVK_ANSI_F: return .toggleFullscreen
        case kVK_ANSI_P: return .togglePin
        case kVK_ANSI_LeftBracket: return .snapLeft
        case kVK_ANSI_RightBracket: return .snapRight
        case kVK_ANSI_Backslash: return .snapMaximize
        default: return nil
        }
    }

    private func mapQuickJumpNumber(keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 1
        case kVK_ANSI_2: return 2
        case kVK_ANSI_3: return 3
        case kVK_ANSI_4: return 4
        case kVK_ANSI_5: return 5
        case kVK_ANSI_6: return 6
        case kVK_ANSI_7: return 7
        case kVK_ANSI_8: return 8
        case kVK_ANSI_9: return 9
        default: return nil
        }
    }

    private func extractPrintableString(from event: CGEvent) -> String? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length > 0 else { return nil }
        let str = String(utf16CodeUnits: buffer, count: length)
        let filtered = str.filter { !$0.isNewline && $0.asciiValue.map({ $0 >= 32 }) ?? true }
        return filtered.isEmpty ? nil : filtered
    }
}
