import AppKit
import Carbon
import Combine
import Foundation
import ServiceManagement

enum SwitcherStyle: String, Codable, CaseIterable, Identifiable {
    case thumbnails
    case appIcons
    case titles

    var id: String { rawValue }
}

enum SwitcherSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case auto

    var id: String { rawValue }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: String { rawValue }
}

enum ReleaseBehavior: String, Codable, CaseIterable, Identifiable {
    case focus
    case hold
    case search

    var id: String { rawValue }
}

enum ScreenDisplayMode: String, Codable, CaseIterable, Identifiable {
    case activeScreen
    case mouseScreen
    case mainScreen

    var id: String { rawValue }
}

enum AppFilterMode: String, Codable, CaseIterable, Identifiable {
    case allApps
    case activeApp

    var id: String { rawValue }
}

enum SpaceFilterMode: String, Codable, CaseIterable, Identifiable {
    case allSpaces
    case activeSpace

    var id: String { rawValue }
}

enum ScreenFilterMode: String, Codable, CaseIterable, Identifiable {
    case allScreens
    case activeScreen

    var id: String { rawValue }
}

enum VisibilityFilter: String, Codable, CaseIterable, Identifiable {
    case show
    case hide
    case showAtEnd

    var id: String { rawValue }
}

enum SortOrder: String, Codable, CaseIterable, Identifiable {
    case recentlyUsed
    case appName
    case windowTitle
    case spaceOrder

    var id: String { rawValue }
}

enum ExceptionHideRule: String, Codable, CaseIterable, Identifiable {
    case never
    case always
    case whenNoOpenWindow

    var id: String { rawValue }
}

enum ExceptionIgnoreShortcutRule: String, Codable, CaseIterable, Identifiable {
    case never
    case always
    case whenFullscreen

    var id: String { rawValue }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case en
    case de
    case es
    case fr
    case it
    case pt
    case nl
    case pl
    case cs
    case hu
    case ro
    case sv
    case tr
    case el
    case ru
    case uk
    case bg
    case hr
    case sr
    case sl
    case sq
    case ja
    case ko
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .fr: return "Français"
        case .it: return "Italiano"
        case .pt: return "Português"
        case .nl: return "Nederlands"
        case .pl: return "Polski"
        case .cs: return "Čeština"
        case .hu: return "Magyar"
        case .ro: return "Română"
        case .sv: return "Svenska"
        case .tr: return "Türkçe"
        case .el: return "Ελληνικά"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .bg: return "Български"
        case .hr: return "Hrvatski"
        case .sr: return "Српски"
        case .sl: return "Slovenščina"
        case .sq: return "Shqip"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }
}

struct ModifierFlags: OptionSet, Codable, Equatable, Hashable {
    let rawValue: UInt64

    static let command = ModifierFlags(rawValue: 1 << 0)
    static let option  = ModifierFlags(rawValue: 1 << 1)
    static let control = ModifierFlags(rawValue: 1 << 2)
    static let shift   = ModifierFlags(rawValue: 1 << 3)

    var displaySymbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option)  { result += "⌥" }
        if contains(.shift)   { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    var cgEventFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.option)  { flags.insert(.maskAlternate) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.shift)   { flags.insert(.maskShift) }
        return flags
    }

    static func from(cgFlags: CGEventFlags) -> ModifierFlags {
        var result: ModifierFlags = []
        if cgFlags.contains(.maskCommand)   { result.insert(.command) }
        if cgFlags.contains(.maskAlternate) { result.insert(.option) }
        if cgFlags.contains(.maskControl)   { result.insert(.control) }
        if cgFlags.contains(.maskShift)     { result.insert(.shift) }
        return result
    }

    static func from(nsFlags: NSEvent.ModifierFlags) -> ModifierFlags {
        var result: ModifierFlags = []
        if nsFlags.contains(.command) { result.insert(.command) }
        if nsFlags.contains(.option)  { result.insert(.option) }
        if nsFlags.contains(.control) { result.insert(.control) }
        if nsFlags.contains(.shift)   { result.insert(.shift) }
        return result
    }
}

struct ShortcutConfig: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var isEnabled: Bool = true
    var holdModifiers: ModifierFlags
    var triggerKeyCode: UInt16

    // Filtering
    var appFilter: AppFilterMode = .allApps
    var spaceFilter: SpaceFilterMode = .allSpaces
    var screenFilter: ScreenFilterMode = .allScreens
    var showMinimized: VisibilityFilter = .show
    var showHidden: VisibilityFilter = .show
    var showFullscreen: VisibilityFilter = .show
    var showWindowlessApps: VisibilityFilter = .showAtEnd

    // Display overrides (nil = use global)
    var styleOverride: SwitcherStyle? = nil
    var releaseBehaviorOverride: ReleaseBehavior? = nil

    // Sorting & Grouping
    var sortOrder: SortOrder = .recentlyUsed
    var groupByApp: Bool = false

    var shortcutLabel: String {
        "\(holdModifiers.displaySymbols) + \(KeyCodeTranslator.symbol(for: triggerKeyCode))"
    }
}

struct AppException: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var bundleIdentifier: String
    var displayName: String
    var hideWindows: ExceptionHideRule = .never
    var ignoreShortcuts: ExceptionIgnoreShortcutRule = .never
}

struct SettingsPayload: Codable {
    // Appearance
    var style: SwitcherStyle = .thumbnails
    var size: SwitcherSize = .auto
    var appearance: AppearanceMode = .system
    var releaseBehavior: ReleaseBehavior = .focus
    var showLivePreview: Bool = false
    var displayScreen: ScreenDisplayMode = .activeScreen
    var enableAnimations: Bool = true
    var showStatusBadges: Bool = true
    var showQuickJumpNumbers: Bool = true
    var showHoverWindowActions: Bool = true
    var showWindowSnappingActions: Bool = true
    var fadeDelayMs: Int = 80
    var maxWidthPercent: Double = 85
    var maxHeightPercent: Double = 78

    // Shortcuts
    var shortcuts: [ShortcutConfig] = SettingsPayload.defaultShortcuts()

    // General
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var backgroundCapture: Bool = true
    var language: AppLanguage = .system

    // Exceptions
    var exceptions: [AppException] = SettingsPayload.defaultExceptions()

    // Pinned window keys (bundleID::title)
    var pinnedWindowKeys: [String] = []

    static func defaultShortcuts() -> [ShortcutConfig] {
        [
            ShortcutConfig(
                name: "Alle Fenster",
                isEnabled: true,
                holdModifiers: [.command],
                triggerKeyCode: UInt16(kVK_Tab),
                appFilter: .allApps,
                spaceFilter: .allSpaces,
                screenFilter: .allScreens,
                showMinimized: .show,
                showHidden: .show,
                showFullscreen: .show,
                showWindowlessApps: .showAtEnd,
                styleOverride: nil,
                releaseBehaviorOverride: nil,
                sortOrder: .recentlyUsed,
                groupByApp: false
            ),
            ShortcutConfig(
                name: "Nur aktive App",
                isEnabled: true,
                holdModifiers: [.option],
                triggerKeyCode: UInt16(kVK_ANSI_Grave),
                appFilter: .activeApp,
                spaceFilter: .allSpaces,
                screenFilter: .allScreens,
                showMinimized: .show,
                showHidden: .show,
                showFullscreen: .show,
                showWindowlessApps: .hide,
                styleOverride: nil,
                releaseBehaviorOverride: nil,
                sortOrder: .recentlyUsed,
                groupByApp: false
            ),
            ShortcutConfig(
                name: "Fenster-Suche",
                isEnabled: true,
                holdModifiers: [.option],
                triggerKeyCode: UInt16(kVK_Tab),
                appFilter: .allApps,
                spaceFilter: .allSpaces,
                screenFilter: .allScreens,
                showMinimized: .show,
                showHidden: .show,
                showFullscreen: .show,
                showWindowlessApps: .showAtEnd,
                styleOverride: nil,
                releaseBehaviorOverride: .search,
                sortOrder: .recentlyUsed,
                groupByApp: false
            )
        ]
    }

    static func defaultExceptions() -> [AppException] {
        [
            AppException(bundleIdentifier: "com.apple.finder", displayName: "Finder", hideWindows: .whenNoOpenWindow, ignoreShortcuts: .never),
            AppException(bundleIdentifier: "com.apple.ScreenSharing", displayName: "Bildschirmfreigabe", hideWindows: .never, ignoreShortcuts: .always),
            AppException(bundleIdentifier: "com.microsoft.rdc.macos", displayName: "Windows App / RDP", hideWindows: .never, ignoreShortcuts: .always),
            AppException(bundleIdentifier: "com.teamviewer.TeamViewer", displayName: "TeamViewer", hideWindows: .never, ignoreShortcuts: .always),
            AppException(bundleIdentifier: "org.virtualbox.app.VirtualBoxVM", displayName: "VirtualBox VM", hideWindows: .never, ignoreShortcuts: .always),
            AppException(bundleIdentifier: "com.parallels.desktop.console", displayName: "Parallels Desktop", hideWindows: .never, ignoreShortcuts: .always),
            AppException(bundleIdentifier: "com.citrix.XenAppViewer", displayName: "Citrix Viewer", hideWindows: .never, ignoreShortcuts: .always)
        ]
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let storageKey = "dev.cmdtab.settings.v2"

    @Published var payload: SettingsPayload {
        didSet {
            save()
            syncLaunchAtLoginIfNeeded(oldValue: oldValue.launchAtLogin)
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(SettingsPayload.self, from: data) {
            self.payload = decoded
        } else {
            self.payload = SettingsPayload()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func resetToDefaults() {
        payload = SettingsPayload()
    }

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    func importJSON(_ data: Data) throws {
        let decoded = try JSONDecoder().decode(SettingsPayload.self, from: data)
        payload = decoded
    }

    func togglePin(for window: WindowInfo) {
        let key = pinKey(for: window)
        if let idx = payload.pinnedWindowKeys.firstIndex(of: key) {
            payload.pinnedWindowKeys.remove(at: idx)
        } else {
            payload.pinnedWindowKeys.append(key)
        }
    }

    func isPinned(_ window: WindowInfo) -> Bool {
        payload.pinnedWindowKeys.contains(pinKey(for: window))
    }

    func pinKey(for window: WindowInfo) -> String {
        "\(window.bundleIdentifier)::\(window.displayTitle)"
    }

    private func syncLaunchAtLoginIfNeeded(oldValue: Bool) {
        guard oldValue != payload.launchAtLogin else { return }
        if #available(macOS 13.0, *) {
            do {
                if payload.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Non-fatal in unsigned/dev builds
            }
        }
    }
}

enum KeyCodeTranslator {
    static func symbol(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ANSI_Grave: return "`"
        case kVK_ISO_Section: return "§"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "Key(\(keyCode))"
        }
    }
}
