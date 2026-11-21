import AppKit
import SwiftUI

@MainActor
final class SwitcherPanelController: HotkeyManagerDelegate {
    static let shared = SwitcherPanelController()

    private let viewModel = SwitcherViewModel()
    private let livePreview = LivePreviewOverlay()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<SwitcherView>?
    private var globalClickMonitor: Any?
    private var currentScreen: NSScreen = NSScreen.main ?? NSScreen.screens[0]

    private(set) var isSwitcherVisible: Bool = false

    var isSearchModeActive: Bool {
        viewModel.isSearchActive
    }

    private init() {
        wireViewModelCallbacks()
    }

    private func wireViewModelCallbacks() {
        viewModel.onSelectAndFocus = { [weak self] window in
            self?.focusAndDismiss(window)
        }
        viewModel.onCloseWindow = { [weak self] window in
            WindowManager.shared.close(window)
            self?.refreshAfterMutation(removingWindowID: window.id)
        }
        viewModel.onMinimizeWindow = { [weak self] window in
            WindowManager.shared.toggleMinimize(window)
            self?.refreshAfterMutation(removingWindowID: nil)
        }
        viewModel.onFullscreenWindow = { [weak self] window in
            WindowManager.shared.toggleFullscreen(window)
            self?.dismiss()
        }
        viewModel.onTogglePin = { [weak self] window in
            AppSettings.shared.togglePin(for: window)
            self?.refreshAfterMutation(removingWindowID: nil)
        }
        viewModel.onSnapWindow = { [weak self] window, pos in
            WindowManager.shared.snap(window, to: pos)
            self?.dismiss()
        }
        viewModel.onSelectionChanged = { [weak self] window in
            guard let self, self.isSwitcherVisible else { return }
            if let window {
                self.livePreview.showPreview(for: window, on: self.currentScreen)
                self.panel?.orderFrontRegardless()
            } else {
                self.livePreview.hide()
            }
        }
    }

    // MARK: - Public Manual Trigger (e.g. from Menu Bar)

    func showManually(openSearch: Bool = false) {
        let shortcut = AppSettings.shared.payload.shortcuts.first ?? SettingsPayload.defaultShortcuts()[0]
        showSwitcher(for: shortcut, reverse: false, forceSearch: openSearch)
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidTrigger(shortcut: ShortcutConfig, reverse: Bool) {
        if isSwitcherVisible {
            viewModel.stepSelection(delta: reverse ? -1 : 1)
            return
        }
        showSwitcher(for: shortcut, reverse: reverse, forceSearch: false)
    }

    func hotkeyDidReleaseHoldModifiers() {
        guard isSwitcherVisible else { return }
        let behavior = viewModel.activeShortcut?.releaseBehaviorOverride ?? AppSettings.shared.payload.releaseBehavior

        switch behavior {
        case .focus:
            if let selected = viewModel.selectedWindow {
                focusAndDismiss(selected)
            } else {
                dismiss()
            }
        case .hold:
            // Stay open until user clicks, presses Enter, or presses Esc
            break
        case .search:
            viewModel.isSearchActive = true
            resizeAndCenterPanel()
        }
    }

    func hotkeyDidPressEscape() {
        dismiss()
    }

    func hotkeyDidPressReturn() {
        if let selected = viewModel.selectedWindow {
            focusAndDismiss(selected)
        } else {
            dismiss()
        }
    }

    func hotkeyDidPressArrow(_ direction: NavigationDirection) {
        let cols = estimatedGridColumns()
        viewModel.moveSelection(direction: direction, columns: cols)
    }

    func hotkeyDidPressActionKey(_ action: SwitcherKeyAction) {
        switch action {
        case .toggleSearch:
            viewModel.isSearchActive.toggle()
            if !viewModel.isSearchActive {
                viewModel.searchQuery = ""
            }
            resizeAndCenterPanel()
            return
        default:
            break
        }

        guard let selected = viewModel.selectedWindow else { return }
        switch action {
        case .closeWindow:
            WindowManager.shared.close(selected)
            refreshAfterMutation(removingWindowID: selected.id)
        case .quitApp:
            WindowManager.shared.quitApp(selected)
            refreshAfterMutation(removingWindowID: selected.id)
        case .minimizeWindow:
            WindowManager.shared.toggleMinimize(selected)
            refreshAfterMutation(removingWindowID: nil)
        case .hideApp:
            WindowManager.shared.toggleHideApp(selected)
            refreshAfterMutation(removingWindowID: nil)
        case .toggleFullscreen:
            WindowManager.shared.toggleFullscreen(selected)
            dismiss()
        case .togglePin:
            AppSettings.shared.togglePin(for: selected)
            refreshAfterMutation(removingWindowID: nil)
        case .snapLeft:
            WindowManager.shared.snap(selected, to: .leftHalf)
            dismiss()
        case .snapRight:
            WindowManager.shared.snap(selected, to: .rightHalf)
            dismiss()
        case .snapMaximize:
            WindowManager.shared.snap(selected, to: .maximize)
            dismiss()
        case .toggleSearch:
            break
        }
    }

    func hotkeyDidPressQuickJump(_ number: Int) {
        let idx = number - 1
        guard viewModel.filteredWindows.indices.contains(idx) else { return }
        focusAndDismiss(viewModel.filteredWindows[idx])
    }

    func hotkeyDidTypeSearchCharacter(_ char: String) {
        viewModel.isSearchActive = true
        viewModel.searchQuery.append(char)
        resizeAndCenterPanel()
    }

    func hotkeyDidPressBackspace() {
        if !viewModel.searchQuery.isEmpty {
            viewModel.searchQuery.removeLast()
            resizeAndCenterPanel()
        }
    }

    // MARK: - Show / Dismiss

    private func showSwitcher(for shortcut: ShortcutConfig, reverse: Bool, forceSearch: Bool) {
        let windows = WindowManager.shared.fetchWindows(for: shortcut)
        let screen = resolveTargetScreen()
        self.currentScreen = screen

        let releaseBehavior = shortcut.releaseBehaviorOverride ?? AppSettings.shared.payload.releaseBehavior
        let openSearch = forceSearch || releaseBehavior == .search

        // Pick index 1 (previous window) when >= 2 windows so Alt+Tab switches immediately to the last window
        let initialIndex: Int
        if windows.count <= 1 {
            initialIndex = 0
        } else {
            initialIndex = reverse ? (windows.count - 1) : 1
        }

        isSwitcherVisible = true
        viewModel.load(windows: windows, shortcut: shortcut, initialSelection: initialIndex, openSearch: openSearch)

        ensurePanel(on: screen)
        resizeAndCenterPanel()

        if let selected = viewModel.selectedWindow {
            livePreview.showPreview(for: selected, on: screen)
        }

        panel?.orderFrontRegardless()
        installClickOutsideMonitor()

        // Capture fresh thumbnails asynchronously so switcher opens with 0ms delay
        let windowIDs = windows.compactMap { $0.windowID != 0 ? $0.windowID : nil }
        ScreenCaptureService.shared.captureThumbnails(for: windowIDs, maxWidth: 640) { [weak self] wid, img in
            self?.viewModel.updateThumbnail(windowID: wid, image: img)
        }
    }

    func dismiss() {
        guard isSwitcherVisible else { return }
        isSwitcherVisible = false
        HotkeyManager.shared.clearActiveSession()
        livePreview.hide()
        panel?.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func focusAndDismiss(_ window: WindowInfo) {
        dismiss()
        WindowManager.shared.focus(window)
    }

    private func refreshAfterMutation(removingWindowID: String?) {
        if let removingWindowID {
            viewModel.allWindows.removeAll { $0.id == removingWindowID }
            viewModel.applySearchFilter()
            if viewModel.allWindows.isEmpty {
                dismiss()
                return
            }
            resizeAndCenterPanel()
        }

        // Re-sync with macOS after a short delay so minimized/hidden states reflect cleanly
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self, self.isSwitcherVisible, let shortcut = self.viewModel.activeShortcut else { return }
            let updated = WindowManager.shared.fetchWindows(for: shortcut)
            if updated.isEmpty {
                self.dismiss()
                return
            }
            let prevIndex = self.viewModel.selectedIndex
            self.viewModel.allWindows = updated
            self.viewModel.applySearchFilter()
            self.viewModel.selectedIndex = min(prevIndex, max(0, self.viewModel.filteredWindows.count - 1))
            self.resizeAndCenterPanel()
        }
    }

    // MARK: - Panel Layout

    private func ensurePanel(on screen: NSScreen) {
        let maxW = screen.visibleFrame.width * CGFloat(AppSettings.shared.payload.maxWidthPercent / 100.0)
        let maxH = screen.visibleFrame.height * CGFloat(AppSettings.shared.payload.maxHeightPercent / 100.0)
        let rootView = SwitcherView(viewModel: viewModel, maxWidth: maxW, maxHeight: maxH)

        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 320),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false // SwiftUI draws crisp shadow matching rounded corners
            p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.hidesOnDeactivate = false
            p.animationBehavior = .none

            let host = NSHostingView(rootView: rootView)
            p.contentView = host
            self.panel = p
            self.hostingView = host
        } else {
            hostingView?.rootView = rootView
        }
    }

    private func resizeAndCenterPanel() {
        guard let panel, let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let vis = currentScreen.visibleFrame

        let w = min(vis.width - 40, max(360, fitting.width))
        let h = min(vis.height - 40, max(120, fitting.height))

        let x = vis.midX - w / 2
        // When live preview is enabled, place the switcher slightly lower so the full preview shines above it!
        let yOffset: CGFloat = AppSettings.shared.payload.showLivePreview ? -vis.height * 0.14 : 0
        let y = max(vis.minY + 32, min(vis.maxY - h - 32, vis.midY - h / 2 + yOffset))

        panel.setFrame(NSRect(x: round(x), y: round(y), width: round(w), height: round(h)), display: true)
    }

    private func resolveTargetScreen() -> NSScreen {
        switch AppSettings.shared.payload.displayScreen {
        case .mouseScreen:
            let mouseLoc = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouseLoc) } ?? NSScreen.main ?? NSScreen.screens[0]
        case .mainScreen:
            return NSScreen.screens.first ?? NSScreen.main!
        case .activeScreen:
            return NSScreen.main ?? NSScreen.screens.first!
        }
    }

    private func estimatedGridColumns() -> Int {
        switch viewModel.effectiveStyle {
        case .titles:
            return 1
        case .appIcons:
            return max(1, viewModel.filteredWindows.count)
        case .thumbnails:
            let maxW = currentScreen.visibleFrame.width * CGFloat(AppSettings.shared.payload.maxWidthPercent / 100.0) - 44
            let cardW: CGFloat = {
                switch AppSettings.shared.payload.size {
                case .small: return 185
                case .medium: return 245
                case .large: return 310
                case .auto:
                    let c = viewModel.filteredWindows.count
                    if c <= 3 { return 310 }
                    if c <= 5 { return 250 }
                    if c <= 8 { return 215 }
                    return 185
                }
            }()
            return max(1, min(viewModel.filteredWindows.count, Int((maxW + 12) / (cardW + 12))))
        }
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismiss()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}
