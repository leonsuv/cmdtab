import AppKit
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import UniformTypeIdentifiers

// Standard private symbol in ApplicationServices used to bridge AXUIElement <-> CGWindowID
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Safe dynamic loader for CoreGraphics Space APIs so we show accurate "Space 1 / Space 2" badges
/// without risking link errors across macOS versions.
private final class SpaceInspector {
    static let shared = SpaceInspector()

    private typealias CGSMainConnectionIDFunc = @convention(c) () -> UInt32
    private typealias CGSCopyManagedDisplaySpacesFunc = @convention(c) (UInt32) -> Unmanaged<CFArray>?
    private typealias CGSCopySpacesForWindowsFunc = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?

    private var mainConnectionID: CGSMainConnectionIDFunc?
    private var copyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFunc?
    private var copySpacesForWindows: CGSCopySpacesForWindowsFunc?

    private init() {
        let handle = dlopen(nil, RTLD_LAZY)
        if let sym = dlsym(handle, "CGSMainConnectionID") {
            mainConnectionID = unsafeBitCast(sym, to: CGSMainConnectionIDFunc.self)
        }
        if let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces") {
            copyManagedDisplaySpaces = unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFunc.self)
        }
        if let sym = dlsym(handle, "CGSCopySpacesForWindows") {
            copySpacesForWindows = unsafeBitCast(sym, to: CGSCopySpacesForWindowsFunc.self)
        }
    }

    struct SpaceSnapshot {
        let spaceNumberByID: [UInt64: Int]
        let activeSpaceIDs: Set<UInt64>
    }

    func snapshot() -> SpaceSnapshot {
        guard let connFunc = mainConnectionID,
              let spacesFunc = copyManagedDisplaySpaces else {
            return SpaceSnapshot(spaceNumberByID: [:], activeSpaceIDs: [])
        }
        let cid = connFunc()
        guard let displays = spacesFunc(cid)?.takeRetainedValue() as? [[String: Any]] else {
            return SpaceSnapshot(spaceNumberByID: [:], activeSpaceIDs: [])
        }

        var map: [UInt64: Int] = [:]
        var active = Set<UInt64>()
        var runningIndex = 1

        for display in displays {
            if let current = display["Current Space"] as? [String: Any],
               let currentID = (current["id64"] as? NSNumber)?.uint64Value ?? (current["ManagedSpaceID"] as? NSNumber)?.uint64Value {
                active.insert(currentID)
            }
            if let spaces = display["Spaces"] as? [[String: Any]] {
                for sp in spaces {
                    if let spID = (sp["id64"] as? NSNumber)?.uint64Value ?? (sp["ManagedSpaceID"] as? NSNumber)?.uint64Value {
                        map[spID] = runningIndex
                        runningIndex += 1
                    }
                }
            }
        }
        return SpaceSnapshot(spaceNumberByID: map, activeSpaceIDs: active)
    }

    func spaceInfo(for windowID: CGWindowID, using snap: SpaceSnapshot) -> (index: Int?, isActive: Bool) {
        guard let connFunc = mainConnectionID,
              let winSpacesFunc = copySpacesForWindows,
              !snap.spaceNumberByID.isEmpty else {
            return (nil, true)
        }
        let cid = connFunc()
        let arr = [NSNumber(value: windowID)] as CFArray
        // mask 0x7 = all spaces (current + other + fullscreen)
        guard let spaceIDs = winSpacesFunc(cid, 0x7, arr)?.takeRetainedValue() as? [NSNumber],
              let first = spaceIDs.first?.uint64Value else {
            return (nil, true)
        }
        let idx = snap.spaceNumberByID[first]
        let isActive = spaceIDs.contains { snap.activeSpaceIDs.contains($0.uint64Value) }
        return (idx, isActive)
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// Tracks most-recently-focused timestamp per windowID (or "app::<pid>" for windowless apps)
    private var mruTimestamps: [String: Date] = [:]
    private var workspaceObserver: NSObjectProtocol?

    private init() {
        startObservingActivation()
    }

    private func startObservingActivation() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.recordAppActivation(app)
            }
        }
    }

    private func recordAppActivation(_ app: NSRunningApplication) {
        let now = Date()
        let pid = app.processIdentifier
        mruTimestamps["app::\(pid)"] = now

        // Also record the focused AX window of this app
        let axApp = AXUIElementCreateApplication(pid)
        var focusedObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedObj) == .success,
           let focusedObj,
           CFGetTypeID(focusedObj) == AXUIElementGetTypeID() {
            let axWin = focusedObj as! AXUIElement
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &wid) == .success, wid != 0 {
                mruTimestamps["win::\(wid)"] = now
            }
        }
    }

    /// Returns whether shortcuts should be ignored for the currently frontmost application based on Exceptions.
    func shouldIgnoreShortcutsForFrontmostApp() -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            return false
        }
        let exceptions = AppSettings.shared.payload.exceptions
        guard let rule = exceptions.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame }) else {
            return false
        }
        switch rule.ignoreShortcuts {
        case .never:
            return false
        case .always:
            return true
        case .whenFullscreen:
            return isFrontmostWindowFullscreen(pid: frontApp.processIdentifier)
        }
    }

    private func isFrontmostWindowFullscreen(pid: pid_t) -> Bool {
        let axApp = AXUIElementCreateApplication(pid)
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedObj) == .success,
              let focusedObj,
              CFGetTypeID(focusedObj) == AXUIElementGetTypeID() else {
            return false
        }
        let axWin = focusedObj as! AXUIElement
        var fullRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, "AXFullScreen" as CFString, &fullRef) == .success,
           let num = fullRef as? NSNumber {
            return num.boolValue
        }
        return false
    }

    /// Collects, filters, and sorts windows according to the given `ShortcutConfig`.
    func fetchWindows(for shortcut: ShortcutConfig) -> [WindowInfo] {
        let settings = AppSettings.shared.payload
        let spaceSnapshot = SpaceInspector.shared.snapshot()
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let activeScreenID = Self.activeScreenDisplayID()
        let selfPID = ProcessInfo.processInfo.processIdentifier

        // 1. Gather CGWindowList metadata (z-order, bounds, titles, on-screen status)
        let cgOptions: CGWindowListOption = [.excludeDesktopElements]
        let cgInfoList = (CGWindowListCopyWindowInfo(cgOptions, kCGNullWindowID) as? [[String: Any]]) ?? []

        var cgByID: [CGWindowID: [String: Any]] = [:]
        var cgOrderIndex: [CGWindowID: Int] = [:]
        for (idx, dict) in cgInfoList.enumerated() {
            guard let wid = (dict[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            cgByID[wid] = dict
            cgOrderIndex[wid] = idx
        }

        // 2. Enumerate regular running apps (including CmdTab itself when its Settings window is open)
        let runningApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isTerminated
        }

        var normalItems: [WindowInfo] = []
        var endItems: [WindowInfo] = []
        var discoveredWindowIDs = Set<CGWindowID>()

        for app in runningApps {
            let pid = app.processIdentifier
            let bundleID = app.bundleIdentifier ?? "pid.\(pid)"
            let appName = app.localizedName ?? bundleID
            let appIcon = app.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
            let isHidden = app.isHidden

            if shortcut.appFilter == .activeApp && pid != frontmostPID {
                continue
            }

            let exception = settings.exceptions.first {
                $0.bundleIdentifier.caseInsensitiveCompare(bundleID) == .orderedSame
            }
            if exception?.hideWindows == .always {
                continue
            }

            // Query AX windows for this app (finds minimized, hidden, other-space windows too!)
            var appWindows: [WindowInfo] = []
            let axApp = AXUIElementCreateApplication(pid)
            var windowsRef: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef)

            if axResult == .success, let axWindows = windowsRef as? [AXUIElement] {
                for axWin in axWindows {
                    guard isValidSwitcherWindow(axWin) else { continue }

                    var wid: CGWindowID = 0
                    _ = _AXUIElementGetWindow(axWin, &wid)

                    let title = axString(axWin, kAXTitleAttribute) ??
                        (wid != 0 ? (cgByID[wid]?[kCGWindowName as String] as? String) : nil) ?? ""

                    // For CmdTab itself, only include the real Settings window (skip floating switcher/preview panels)
                    if pid == selfPID && title != "CmdTab" {
                        continue
                    }
                    let isMinimized = axBool(axWin, kAXMinimizedAttribute) ?? false
                    let isFullscreen = axBool(axWin, "AXFullScreen") ?? false
                    let frame = axFrame(axWin) ?? cgBounds(cgByID[wid])

                    // Skip tiny helper / invisible floating strips
                    if !isMinimized && (frame.width < 60 || frame.height < 40) {
                        continue
                    }

                    let spaceInfo: (index: Int?, isActive: Bool) = wid != 0
                        ? SpaceInspector.shared.spaceInfo(for: wid, using: spaceSnapshot)
                        : (index: nil, isActive: true)
                    let screenID = Self.displayID(for: frame)

                    let key = wid != 0 ? "win::\(wid)" : "ax::\(pid)::\(title)"
                    let mruDate = mruTimestamps[key]
                        ?? mruTimestamps["app::\(pid)"]
                        ?? Date(timeIntervalSince1970: Double(10_000 - (cgOrderIndex[wid] ?? 9_999)))

                    var info = WindowInfo(
                        id: key,
                        windowID: wid,
                        pid: pid,
                        bundleIdentifier: bundleID,
                        appName: appName,
                        title: title,
                        appIcon: appIcon,
                        thumbnail: wid != 0 ? ScreenCaptureService.shared.cachedThumbnail(for: wid) : nil,
                        frame: frame,
                        isMinimized: isMinimized,
                        isHidden: isHidden,
                        isFullscreen: isFullscreen,
                        isWindowlessApp: false,
                        spaceIndex: spaceInfo.index,
                        isOnActiveSpace: spaceInfo.isActive,
                        screenID: screenID,
                        axWindow: axWin,
                        lastFocusedAt: mruDate,
                        isPinned: false
                    )
                    info.isPinned = AppSettings.shared.isPinned(info)
                    if wid != 0 {
                        discoveredWindowIDs.insert(wid)
                    }
                    appWindows.append(info)
                }
            }

            // Fallback to CGWindowList if AX returned nothing (e.g. Accessibility not yet granted)
            if appWindows.isEmpty {
                for (idx, dict) in cgInfoList.enumerated() {
                    guard let ownerPID = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                          ownerPID == pid,
                          let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue,
                          layer == 0,
                          let wid = (dict[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                        continue
                    }
                    let frame = cgBounds(dict)
                    guard frame.width >= 80 && frame.height >= 60 else { continue }
                    let title = (dict[kCGWindowName as String] as? String) ?? ""
                    let spaceInfo = SpaceInspector.shared.spaceInfo(for: wid, using: spaceSnapshot)
                    let key = "win::\(wid)"
                    let mruDate = mruTimestamps[key]
                        ?? mruTimestamps["app::\(pid)"]
                        ?? Date(timeIntervalSince1970: Double(10_000 - idx))

                    var info = WindowInfo(
                        id: key,
                        windowID: wid,
                        pid: pid,
                        bundleIdentifier: bundleID,
                        appName: appName,
                        title: title,
                        appIcon: appIcon,
                        thumbnail: ScreenCaptureService.shared.cachedThumbnail(for: wid),
                        frame: frame,
                        isMinimized: false,
                        isHidden: isHidden,
                        isFullscreen: false,
                        isWindowlessApp: false,
                        spaceIndex: spaceInfo.index,
                        isOnActiveSpace: spaceInfo.isActive,
                        screenID: Self.displayID(for: frame),
                        axWindow: nil,
                        lastFocusedAt: mruDate,
                        isPinned: false
                    )
                    info.isPinned = AppSettings.shared.isPinned(info)
                    discoveredWindowIDs.insert(wid)
                    appWindows.append(info)
                }
            }

            // Handle windowless apps
            if appWindows.isEmpty {
                if exception?.hideWindows == .whenNoOpenWindow {
                    continue
                }
                if shortcut.showWindowlessApps != .hide {
                    var info = WindowInfo(
                        id: "app::\(pid)",
                        windowID: 0,
                        pid: pid,
                        bundleIdentifier: bundleID,
                        appName: appName,
                        title: appName,
                        appIcon: appIcon,
                        thumbnail: nil,
                        frame: .zero,
                        isMinimized: false,
                        isHidden: isHidden,
                        isFullscreen: false,
                        isWindowlessApp: true,
                        spaceIndex: nil,
                        isOnActiveSpace: true,
                        screenID: nil,
                        axWindow: nil,
                        lastFocusedAt: mruTimestamps["app::\(pid)"] ?? .distantPast,
                        isPinned: false
                    )
                    info.isPinned = AppSettings.shared.isPinned(info)
                    if shortcut.showWindowlessApps == .showAtEnd {
                        endItems.append(info)
                    } else {
                        normalItems.append(info)
                    }
                }
                continue
            }

            // Apply per-window filters
            for win in appWindows {
                if shortcut.spaceFilter == .activeSpace && !win.isOnActiveSpace && !win.isMinimized {
                    continue
                }
                if shortcut.screenFilter == .activeScreen,
                   let activeScreenID,
                   let winScreenID = win.screenID,
                   winScreenID != activeScreenID {
                    continue
                }

                var sendToEnd = false
                if win.isMinimized {
                    switch shortcut.showMinimized {
                    case .hide: continue
                    case .showAtEnd: sendToEnd = true
                    case .show: break
                    }
                }
                if win.isHidden {
                    switch shortcut.showHidden {
                    case .hide: continue
                    case .showAtEnd: sendToEnd = true
                    case .show: break
                    }
                }
                if win.isFullscreen {
                    switch shortcut.showFullscreen {
                    case .hide: continue
                    case .showAtEnd: sendToEnd = true
                    case .show: break
                    }
                }

                if sendToEnd {
                    endItems.append(win)
                } else {
                    normalItems.append(win)
                }
            }
        }

        ScreenCaptureService.shared.pruneCache(keeping: discoveredWindowIDs)

        let sortedNormal = sortWindows(normalItems, by: shortcut.sortOrder, groupByApp: shortcut.groupByApp)
        let sortedEnd = sortWindows(endItems, by: shortcut.sortOrder, groupByApp: shortcut.groupByApp)
        return sortedNormal + sortedEnd
    }

    private func sortWindows(_ list: [WindowInfo], by order: SortOrder, groupByApp: Bool) -> [WindowInfo] {
        list.sorted { a, b in
            // Pinned windows always stay first
            if a.isPinned != b.isPinned {
                return a.isPinned && !b.isPinned
            }
            if groupByApp && a.appName != b.appName {
                return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
            }
            switch order {
            case .recentlyUsed:
                if a.lastFocusedAt != b.lastFocusedAt {
                    return a.lastFocusedAt > b.lastFocusedAt
                }
                return a.appName.localizedCaseInsensitiveCompare(b.appName) == .orderedAscending
            case .appName:
                let cmp = a.appName.localizedCaseInsensitiveCompare(b.appName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            case .windowTitle:
                return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
            case .spaceOrder:
                let sa = a.spaceIndex ?? 999
                let sb = b.spaceIndex ?? 999
                if sa != sb { return sa < sb }
                return a.lastFocusedAt > b.lastFocusedAt
            }
        }
    }

    // MARK: - Window Actions

    func focus(_ window: WindowInfo) {
        let now = Date()
        mruTimestamps[window.id] = now
        mruTimestamps["app::\(window.pid)"] = now

        if window.pid == ProcessInfo.processInfo.processIdentifier {
            SettingsWindowController.shared.show()
            return
        }

        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }

        if app.isHidden {
            app.unhide()
        }

        let axApp = AXUIElementCreateApplication(window.pid)

        // Resolve AX window (or fall back to the app's first minimized/standard window)
        var targetAXWin = window.axWindow
        if targetAXWin == nil {
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let axWindows = windowsRef as? [AXUIElement] {
                if window.windowID != 0 {
                    targetAXWin = axWindows.first { el in
                        var wid: CGWindowID = 0
                        return _AXUIElementGetWindow(el, &wid) == .success && wid == window.windowID
                    }
                }
                if targetAXWin == nil {
                    targetAXWin = axWindows.first { axBool($0, kAXMinimizedAttribute) == true } ?? axWindows.first
                }
            }
        }

        // Always unminimize & raise the target window
        var wasMinimized = window.isMinimized
        if let axWin = targetAXWin {
            if axBool(axWin, kAXMinimizedAttribute) == true {
                wasMinimized = true
            }
            if wasMinimized {
                AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(axWin, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }

        // Force-activate the target application even when CmdTab is a non-activating overlay panel
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = app.activate(options: [.activateIgnoringOtherApps])

        if wasMinimized, let axWin = targetAXWin {
            // Follow-up raise after macOS finishes unminimizing from the Dock
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                _ = app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    func close(_ window: WindowInfo) {
        guard let axWin = window.axWindow else { return }
        var closeButtonRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeButtonRef) == .success,
           let closeButtonRef,
           CFGetTypeID(closeButtonRef) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(closeButtonRef as! AXUIElement, kAXPressAction as CFString)
        }
    }

    func toggleMinimize(_ window: WindowInfo) {
        guard let axWin = window.axWindow else { return }
        let target: CFBoolean = window.isMinimized ? kCFBooleanFalse : kCFBooleanTrue
        AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, target)
    }

    func toggleFullscreen(_ window: WindowInfo) {
        guard let axWin = window.axWindow else { return }
        let target: CFBoolean = window.isFullscreen ? kCFBooleanFalse : kCFBooleanTrue
        if AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, target) != .success {
            // Fallback: press zoom/fullscreen button
            var btnRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWin, kAXFullScreenButtonAttribute as CFString, &btnRef) == .success,
               let btnRef,
               CFGetTypeID(btnRef) == AXUIElementGetTypeID() {
                AXUIElementPerformAction(btnRef as! AXUIElement, kAXPressAction as CFString)
            }
        }
    }

    func toggleHideApp(_ window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        if app.isHidden {
            app.unhide()
        } else {
            app.hide()
        }
    }

    func quitApp(_ window: WindowInfo) {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else { return }
        app.terminate()
    }

    /// Bonus Feature: Snap any window to Left Half, Right Half, Maximize, or Center directly from the switcher!
    func snap(_ window: WindowInfo, to position: WindowSnapPosition) {
        guard let axWin = window.axWindow else { return }
        if window.isMinimized {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if window.isFullscreen {
            AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanFalse)
        }

        let targetScreen = Self.screen(for: window.frame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }

        // Convert Cocoa visibleFrame (bottom-left origin) to Accessibility/Quartz coordinates (top-left origin of primary screen)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let vis = screen.visibleFrame
        let axVisible = CGRect(
            x: vis.origin.x,
            y: primaryHeight - (vis.origin.y + vis.height),
            width: vis.width,
            height: vis.height
        )

        let targetRect: CGRect
        switch position {
        case .leftHalf:
            targetRect = CGRect(x: axVisible.minX, y: axVisible.minY, width: axVisible.width / 2, height: axVisible.height)
        case .rightHalf:
            targetRect = CGRect(x: axVisible.minX + axVisible.width / 2, y: axVisible.minY, width: axVisible.width / 2, height: axVisible.height)
        case .topHalf:
            targetRect = CGRect(x: axVisible.minX, y: axVisible.minY, width: axVisible.width, height: axVisible.height / 2)
        case .bottomHalf:
            targetRect = CGRect(x: axVisible.minX, y: axVisible.minY + axVisible.height / 2, width: axVisible.width, height: axVisible.height / 2)
        case .maximize:
            targetRect = axVisible
        case .center:
            let w = min(axVisible.width * 0.72, max(window.frame.width, 800))
            let h = min(axVisible.height * 0.78, max(window.frame.height, 600))
            targetRect = CGRect(
                x: axVisible.minX + (axVisible.width - w) / 2,
                y: axVisible.minY + (axVisible.height - h) / 2,
                width: w,
                height: h
            )
        }

        var origin = targetRect.origin
        var size = targetRect.size
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sizeVal)
        }
        focus(window)
    }

    // MARK: - AX & Geometry Helpers

    private func isValidSwitcherWindow(_ axWin: AXUIElement) -> Bool {
        let role = axString(axWin, kAXRoleAttribute)
        if let role, role != kAXWindowRole as String {
            return false
        }
        let subrole = axString(axWin, kAXSubroleAttribute)
        if let subrole {
            let allowed: Set<String> = [
                kAXStandardWindowSubrole as String,
                kAXDialogSubrole as String
            ]
            if !allowed.contains(subrole) {
                return false
            }
        }
        return true
    }

    private func axString(_ element: AXUIElement, _ attr: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return ref as? String
    }

    private func axBool(_ element: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.boolValue
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func cgBounds(_ dict: [String: Any]?) -> CGRect {
        guard let dict,
              let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary else {
            return .zero
        }
        var rect = CGRect.zero
        CGRectMakeWithDictionaryRepresentation(boundsDict, &rect)
        return rect
    }

    private static func activeScreenDisplayID() -> CGDirectDisplayID? {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    private static func screen(for axFrame: CGRect) -> NSScreen? {
        guard !axFrame.isEmpty else { return NSScreen.main }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaCenter = CGPoint(x: axFrame.midX, y: primaryHeight - axFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) } ?? NSScreen.main
    }

    private static func displayID(for axFrame: CGRect) -> CGDirectDisplayID? {
        screen(for: axFrame)?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
