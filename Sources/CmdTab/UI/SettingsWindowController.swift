import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        // Show in Dock & system Cmd+Tab while the Settings window is open
        NSApp.setActivationPolicy(.regular)

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            bringToFront(existing)
            return
        }

        let contentView = SettingsView()
        let hostingController = NSHostingController(rootView: contentView)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "CmdTab"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 760, height: 540)
        win.contentViewController = hostingController
        win.delegate = self
        win.center()

        self.window = win
        bringToFront(win)
    }

    private func bringToFront(_ win: NSWindow) {
        win.makeKeyAndOrderFront(nil)
        win.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        // Return to menu-bar-only accessory mode once Settings is closed
        NSApp.setActivationPolicy(.accessory)
    }
}
