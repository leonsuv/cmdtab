import AppKit
import Combine
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Initialize core services
        _ = WindowManager.shared
        HotkeyManager.shared.delegate = SwitcherPanelController.shared

        setupMenuBar()
        observeSettingsAndPermissions()

        // Try starting global hotkey event tap immediately
        if PermissionsManager.shared.hasAccessibility {
            _ = HotkeyManager.shared.start()
        } else {
            PermissionsManager.shared.startPolling(interval: 1.5)
        }

        if AppSettings.shared.payload.backgroundCapture {
            ScreenCaptureService.shared.startBackgroundCaptureIfNeeded()
        }

        // Open settings window on launch so the user sees the app immediately (and any missing permissions)
        SettingsWindowController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.stop()
        ScreenCaptureService.shared.stopBackgroundCapture()
        PermissionsManager.shared.stopPolling()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        updateMenuBarVisibility(AppSettings.shared.payload.showMenuBarIcon)
    }

    private func updateMenuBarVisibility(_ visible: Bool) {
        if visible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let button = item.button {
                    let img = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "CmdTab")
                    img?.isTemplate = true
                    button.image = img
                    button.toolTip = "CmdTab"
                }
                item.menu = buildStatusMenu()
                statusItem = item
            } else {
                statusItem?.menu = buildStatusMenu()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let showItem = NSMenuItem(
            title: L10n.t("Wechsler öffnen", "Open Switcher"),
            action: #selector(openSwitcherAction),
            keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)

        let searchItem = NSMenuItem(
            title: L10n.t("Fenster suchen…", "Search Windows…"),
            action: #selector(openSearchAction),
            keyEquivalent: ""
        )
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.t("Einstellungen…", "Settings…"),
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.t("CmdTab beenden", "Quit CmdTab"),
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func observeSettingsAndPermissions() {
        AppSettings.shared.$payload
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in
                self?.updateMenuBarVisibility(visible)
            }
            .store(in: &cancellables)

        AppSettings.shared.$payload
            .map(\.backgroundCapture)
            .removeDuplicates()
            .sink { enabled in
                if enabled {
                    ScreenCaptureService.shared.startBackgroundCaptureIfNeeded()
                } else {
                    ScreenCaptureService.shared.stopBackgroundCapture()
                }
            }
            .store(in: &cancellables)

        AppSettings.shared.$payload
            .map(\.language)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.statusItem?.menu = self?.buildStatusMenu()
            }
            .store(in: &cancellables)

        PermissionsManager.shared.$hasAccessibility
            .removeDuplicates()
            .sink { granted in
                if granted {
                    if !HotkeyManager.shared.isRunning {
                        _ = HotkeyManager.shared.start()
                    }
                    if PermissionsManager.shared.hasScreenRecording {
                        PermissionsManager.shared.stopPolling()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Menu Actions

    @objc private func openSwitcherAction() {
        SwitcherPanelController.shared.showManually(openSearch: false)
    }

    @objc private func openSearchAction() {
        SwitcherPanelController.shared.showManually(openSearch: true)
    }

    @objc private func openSettingsAction() {
        SettingsWindowController.shared.show()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        NSApp.terminate(nil)
    }
}
