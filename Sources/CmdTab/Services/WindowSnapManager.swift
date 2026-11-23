import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@_silgen_name("_AXUIElementGetWindow")
private func _CmdTabSnapGetWindowID(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
final class WindowSnapManager {
    static let shared = WindowSnapManager()

    /// Original pre-snap AX frames keyed by CGWindowID (for Restore & Restore-on-Drag)
    private var originalFrames: [CGWindowID: CGRect] = [:]

    /// Last snap action + timestamp per window for repeated command cycling
    private struct LastSnapRecord {
        let action: SnapAction
        let cycleStep: Int
        let timestamp: Date
    }
    private var lastSnapByWindow: [CGWindowID: LastSnapRecord] = [:]

    // Drag-to-snap state
    private var mouseDownMonitor: Any?
    private var mouseDraggedMonitor: Any?
    private var mouseUpMonitor: Any?

    private var draggedWindow: AXUIElement?
    private var draggedWindowID: CGWindowID = 0
    private var dragStartWindowOrigin: CGPoint = .zero
    private var isDraggingWindow: Bool = false
    private var didRestoreDuringCurrentDrag: Bool = false
    private var activeHoverZone: SnapEdgeZone?
    private var activeHoverScreen: NSScreen?

    private init() {}

    // MARK: - Lifecycle

    func startMonitoring() {
        stopMonitoring()

        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseDown(event)
            }
        }
        mouseDraggedMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseDragged(event)
            }
        }
        mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseUp(event)
            }
        }
    }

    func stopMonitoring() {
        if let m = mouseDownMonitor { NSEvent.removeMonitor(m); mouseDownMonitor = nil }
        if let m = mouseDraggedMonitor { NSEvent.removeMonitor(m); mouseDraggedMonitor = nil }
        if let m = mouseUpMonitor { NSEvent.removeMonitor(m); mouseUpMonitor = nil }
        resetDragState()
    }

    // MARK: - Execute Snap Action on Frontmost Window

    func execute(_ action: SnapAction, on explicitWindow: AXUIElement? = nil) {
        guard action != .none else { return }
        let snapSettings = AppSettings.shared.payload.snapping
        guard snapSettings.isEnabled else { return }

        guard let axWin = explicitWindow ?? frontmostFocusedWindow() else { return }
        guard let currentAXFrame = axFrame(of: axWin) else { return }

        var wid: CGWindowID = 0
        _ = _CmdTabSnapGetWindowID(axWin, &wid)

        // Restore original frame
        if action == .restore {
            if wid != 0, let orig = originalFrames.removeValue(forKey: wid) {
                setAXFrame(axWin, to: orig)
                lastSnapByWindow.removeValue(forKey: wid)
            }
            return
        }

        // Unminimize / exit fullscreen if needed
        if axBool(axWin, kAXMinimizedAttribute) == true {
            AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if axBool(axWin, "AXFullScreen") == true {
            AXUIElementSetAttributeValue(axWin, "AXFullScreen" as CFString, kCFBooleanFalse)
        }

        let currentScreen = screen(forAXRect: currentAXFrame) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen = currentScreen else { return }

        // Multi-display move
        if action == .nextDisplay || action == .previousDisplay {
            moveWindow(axWin, windowID: wid, currentAXFrame: currentAXFrame, from: screen, forward: action == .nextDisplay, settings: snapSettings)
            return
        }

        // Save original frame before first snap
        if wid != 0 && originalFrames[wid] == nil {
            originalFrames[wid] = currentAXFrame
        }

        // Handle repeated command behavior
        var effectiveAction = action
        var nextCycleStep = 0
        if wid != 0, let prev = lastSnapByWindow[wid],
           prev.action == action,
           Date().timeIntervalSince(prev.timestamp) < 2.5 {
            switch snapSettings.repeatedCommandBehavior {
            case .doNothing:
                break
            case .cycleThirds:
                if action == .leftHalf {
                    nextCycleStep = (prev.cycleStep + 1) % 3
                    effectiveAction = [SnapAction.leftHalf, .firstTwoThirds, .firstThird][nextCycleStep]
                } else if action == .rightHalf {
                    nextCycleStep = (prev.cycleStep + 1) % 3
                    effectiveAction = [SnapAction.rightHalf, .lastTwoThirds, .lastThird][nextCycleStep]
                }
            case .moveToAdjacentDisplay:
                if action == .leftHalf || action == .rightHalf {
                    moveWindow(axWin, windowID: wid, currentAXFrame: currentAXFrame, from: screen, forward: action == .rightHalf, settings: snapSettings)
                    lastSnapByWindow.removeValue(forKey: wid)
                    return
                }
            }
        }

        let targetAXRect = computeAXRect(for: effectiveAction, on: screen, currentAXFrame: currentAXFrame, settings: snapSettings)
        setAXFrame(axWin, to: targetAXRect)

        if wid != 0 {
            lastSnapByWindow[wid] = LastSnapRecord(action: action, cycleStep: nextCycleStep, timestamp: Date())
        }
    }

    // MARK: - Geometry Calculation

    private func computeAXRect(
        for action: SnapAction,
        on screen: NSScreen,
        currentAXFrame: CGRect,
        settings: WindowSnappingSettings
    ) -> CGRect {
        let vis = usableAXVisibleFrame(for: screen, settings: settings)
        let gap = CGFloat(max(0, settings.windowGap))
        let halfGap = gap / 2.0

        switch action {
        case .leftHalf:
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: vis.width / 2 - gap - halfGap, height: vis.height - gap * 2)
        case .rightHalf:
            return CGRect(x: vis.midX + halfGap, y: vis.minY + gap, width: vis.width / 2 - gap - halfGap, height: vis.height - gap * 2)
        case .centerHalf:
            let w = vis.width / 2
            return CGRect(x: vis.minX + (vis.width - w) / 2, y: vis.minY + gap, width: w, height: vis.height - gap * 2)
        case .topHalf:
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: vis.width - gap * 2, height: vis.height / 2 - gap - halfGap)
        case .bottomHalf:
            return CGRect(x: vis.minX + gap, y: vis.midY + halfGap, width: vis.width - gap * 2, height: vis.height / 2 - gap - halfGap)

        case .topLeft:
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: vis.width / 2 - gap - halfGap, height: vis.height / 2 - gap - halfGap)
        case .topRight:
            return CGRect(x: vis.midX + halfGap, y: vis.minY + gap, width: vis.width / 2 - gap - halfGap, height: vis.height / 2 - gap - halfGap)
        case .bottomLeft:
            return CGRect(x: vis.minX + gap, y: vis.midY + halfGap, width: vis.width / 2 - gap - halfGap, height: vis.height / 2 - gap - halfGap)
        case .bottomRight:
            return CGRect(x: vis.midX + halfGap, y: vis.midY + halfGap, width: vis.width / 2 - gap - halfGap, height: vis.height / 2 - gap - halfGap)

        case .firstThird:
            let w = (vis.width - gap * 4) / 3
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: w, height: vis.height - gap * 2)
        case .centerThird:
            let w = (vis.width - gap * 4) / 3
            return CGRect(x: vis.minX + gap * 2 + w, y: vis.minY + gap, width: w, height: vis.height - gap * 2)
        case .lastThird:
            let w = (vis.width - gap * 4) / 3
            return CGRect(x: vis.minX + gap * 3 + w * 2, y: vis.minY + gap, width: w, height: vis.height - gap * 2)
        case .firstTwoThirds:
            let w = (vis.width - gap * 3) * (2.0 / 3.0)
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: w, height: vis.height - gap * 2)
        case .lastTwoThirds:
            let w = (vis.width - gap * 3) * (2.0 / 3.0)
            return CGRect(x: vis.maxX - gap - w, y: vis.minY + gap, width: w, height: vis.height - gap * 2)

        case .maximize:
            return CGRect(x: vis.minX + gap, y: vis.minY + gap, width: vis.width - gap * 2, height: vis.height - gap * 2)
        case .almostMaximize:
            let w = vis.width * 0.90
            let h = vis.height * 0.90
            return CGRect(x: vis.midX - w / 2, y: vis.midY - h / 2, width: w, height: h)
        case .maximizeHeight:
            return CGRect(x: currentAXFrame.origin.x, y: vis.minY + gap, width: currentAXFrame.width, height: vis.height - gap * 2)
        case .smaller:
            let dw = max(40, vis.width * 0.08)
            let dh = max(30, vis.height * 0.08)
            let newW = max(320, currentAXFrame.width - dw)
            let newH = max(240, currentAXFrame.height - dh)
            return CGRect(x: currentAXFrame.midX - newW / 2, y: currentAXFrame.midY - newH / 2, width: newW, height: newH)
        case .larger:
            let dw = max(40, vis.width * 0.08)
            let dh = max(30, vis.height * 0.08)
            let newW = min(vis.width - gap * 2, currentAXFrame.width + dw)
            let newH = min(vis.height - gap * 2, currentAXFrame.height + dh)
            let x = max(vis.minX + gap, min(vis.maxX - gap - newW, currentAXFrame.midX - newW / 2))
            let y = max(vis.minY + gap, min(vis.maxY - gap - newH, currentAXFrame.midY - newH / 2))
            return CGRect(x: x, y: y, width: newW, height: newH)
        case .center:
            let w = min(vis.width - gap * 2, currentAXFrame.width)
            let h = min(vis.height - gap * 2, currentAXFrame.height)
            return CGRect(x: vis.midX - w / 2, y: vis.midY - h / 2, width: w, height: h)
        case .restore, .nextDisplay, .previousDisplay, .none:
            return currentAXFrame
        }
    }

    private func moveWindow(
        _ axWin: AXUIElement,
        windowID: CGWindowID,
        currentAXFrame: CGRect,
        from currentScreen: NSScreen,
        forward: Bool,
        settings: WindowSnappingSettings
    ) {
        let screens = NSScreen.screens
        guard screens.count > 1,
              let curIdx = screens.firstIndex(of: currentScreen) else { return }

        let nextIdx = forward ? (curIdx + 1) % screens.count : (curIdx - 1 + screens.count) % screens.count
        let targetScreen = screens[nextIdx]

        let curVis = usableAXVisibleFrame(for: currentScreen, settings: settings)
        let tgtVis = usableAXVisibleFrame(for: targetScreen, settings: settings)

        let relX = curVis.width > 0 ? (currentAXFrame.minX - curVis.minX) / curVis.width : 0
        let relY = curVis.height > 0 ? (currentAXFrame.minY - curVis.minY) / curVis.height : 0
        let relW = curVis.width > 0 ? min(1.0, currentAXFrame.width / curVis.width) : 0.6
        let relH = curVis.height > 0 ? min(1.0, currentAXFrame.height / curVis.height) : 0.7

        let newW = max(320, tgtVis.width * relW)
        let newH = max(240, tgtVis.height * relH)
        let newX = max(tgtVis.minX, min(tgtVis.maxX - newW, tgtVis.minX + tgtVis.width * relX))
        let newY = max(tgtVis.minY, min(tgtVis.maxY - newH, tgtVis.minY + tgtVis.height * relY))

        let newRect = CGRect(x: newX, y: newY, width: newW, height: newH)
        setAXFrame(axWin, to: newRect)

        if settings.moveCursorAcrossScreens {
            CGWarpMouseCursorPosition(CGPoint(x: newRect.midX, y: newRect.midY))
        }
    }

    // MARK: - Drag-to-Screen-Edge Snap Areas & Double-Click Titlebar

    private func handleMouseDown(_ event: NSEvent) {
        let snapSettings = AppSettings.shared.payload.snapping
        guard snapSettings.isEnabled else { return }
        guard PermissionsManager.shared.hasAccessibility else { return }

        // Double-click titlebar to maximize / restore
        if snapSettings.doubleClickTitleBarToMaximize && event.clickCount == 2 {
            if let axWin = frontmostFocusedWindow(),
               let frame = axFrame(of: axWin) {
                let mouseAX = cocoaPointToAX(NSEvent.mouseLocation)
                let titleBarRect = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 34)
                if titleBarRect.contains(mouseAX) {
                    var wid: CGWindowID = 0
                    _ = _CmdTabSnapGetWindowID(axWin, &wid)
                    if wid != 0 && originalFrames[wid] != nil {
                        execute(.restore, on: axWin)
                    } else {
                        execute(.maximize, on: axWin)
                    }
                    return
                }
            }
        }

        guard snapSettings.dragToSnapEnabled else { return }

        // Record frontmost window frame at mouse-down so we can detect if the user is actually dragging it
        resetDragState()
        if let axWin = frontmostFocusedWindow(),
           let frame = axFrame(of: axWin) {
            let mouseAX = cocoaPointToAX(NSEvent.mouseLocation)
            // Only track drag if mouse down is inside the window's upper region (titlebar/toolbar)
            if frame.contains(mouseAX) && mouseAX.y <= frame.minY + 72 {
                draggedWindow = axWin
                var wid: CGWindowID = 0
                _ = _CmdTabSnapGetWindowID(axWin, &wid)
                draggedWindowID = wid
                dragStartWindowOrigin = frame.origin
            }
        }
    }

    private func handleMouseDragged(_ event: NSEvent) {
        let snapSettings = AppSettings.shared.payload.snapping
        guard snapSettings.isEnabled && snapSettings.dragToSnapEnabled else { return }
        guard let axWin = draggedWindow else { return }

        // Verify the window actually moved (confirms window drag rather than text selection)
        if !isDraggingWindow {
            guard let curFrame = axFrame(of: axWin) else { return }
            let dx = abs(curFrame.origin.x - dragStartWindowOrigin.x)
            let dy = abs(curFrame.origin.y - dragStartWindowOrigin.y)
            guard dx > 6 || dy > 6 else { return }
            isDraggingWindow = true

            // Restore original size when pulling away a previously snapped window
            if snapSettings.restoreOnDrag && !didRestoreDuringCurrentDrag && draggedWindowID != 0,
               let orig = originalFrames.removeValue(forKey: draggedWindowID) {
                didRestoreDuringCurrentDrag = true
                var origSize = orig.size
                if let sizeVal = AXValueCreate(.cgSize, &origSize) {
                    AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, sizeVal)
                }
            }
        }

        let mouseCocoa = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseCocoa) }) ?? NSScreen.main else {
            clearHoverZone()
            return
        }

        if let zone = detectEdgeZone(mouseCocoa: mouseCocoa, on: screen) {
            let action = snapSettings.action(for: zone)
            guard action != .none else {
                clearHoverZone()
                return
            }

            if activeHoverZone != zone || activeHoverScreen != screen {
                activeHoverZone = zone
                activeHoverScreen = screen
                let axPreview = computeAXRect(for: action, on: screen, currentAXFrame: .zero, settings: snapSettings)
                let cocoaPreview = axRectToCocoa(axPreview)
                SnapFootprintOverlay.shared.show(cocoaRect: cocoaPreview, animated: snapSettings.animateFootprint)

                if snapSettings.hapticFeedback {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
            }
        } else {
            clearHoverZone()
        }
    }

    private func handleMouseUp(_ event: NSEvent) {
        defer { resetDragState() }

        let snapSettings = AppSettings.shared.payload.snapping
        guard snapSettings.isEnabled && snapSettings.dragToSnapEnabled else { return }
        guard isDraggingWindow,
              let axWin = draggedWindow,
              let zone = activeHoverZone,
              let screen = activeHoverScreen else {
            return
        }

        let action = snapSettings.action(for: zone)
        guard action != .none else { return }

        if draggedWindowID != 0 && originalFrames[draggedWindowID] == nil,
           let curFrame = axFrame(of: axWin) {
            originalFrames[draggedWindowID] = curFrame
        }

        let targetRect = computeAXRect(for: action, on: screen, currentAXFrame: axFrame(of: axWin) ?? .zero, settings: snapSettings)
        setAXFrame(axWin, to: targetRect)
    }

    private func clearHoverZone() {
        if activeHoverZone != nil {
            activeHoverZone = nil
            activeHoverScreen = nil
            SnapFootprintOverlay.shared.hide()
        }
    }

    private func resetDragState() {
        clearHoverZone()
        draggedWindow = nil
        draggedWindowID = 0
        isDraggingWindow = false
        didRestoreDuringCurrentDrag = false
    }

    private func detectEdgeZone(mouseCocoa: NSPoint, on screen: NSScreen) -> SnapEdgeZone? {
        let f = screen.frame
        let edgeMargin: CGFloat = 18
        let cornerSize: CGFloat = 120

        let nearLeft = mouseCocoa.x <= f.minX + edgeMargin
        let nearRight = mouseCocoa.x >= f.maxX - edgeMargin
        let nearTop = mouseCocoa.y >= f.maxY - edgeMargin - 24 // account for menu bar
        let nearBottom = mouseCocoa.y <= f.minY + edgeMargin

        let inTopBand = mouseCocoa.y >= f.maxY - cornerSize
        let inBottomBand = mouseCocoa.y <= f.minY + cornerSize
        let inLeftBand = mouseCocoa.x <= f.minX + cornerSize
        let inRightBand = mouseCocoa.x >= f.maxX - cornerSize

        if (nearLeft && inTopBand) || (nearTop && inLeftBand) { return .topLeft }
        if (nearRight && inTopBand) || (nearTop && inRightBand) { return .topRight }
        if (nearLeft && inBottomBand) || (nearBottom && inLeftBand) { return .bottomLeft }
        if (nearRight && inBottomBand) || (nearBottom && inRightBand) { return .bottomRight }

        if nearTop { return .top }
        if nearLeft { return .left }
        if nearRight { return .right }
        if nearBottom { return .bottom }

        return nil
    }

    // MARK: - AX & Coordinate Helpers

    private func frontmostFocusedWindow() -> AXUIElement? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(frontApp.processIdentifier)
        var focusedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedRef) == .success,
           let focusedRef,
           CFGetTypeID(focusedRef) == AXUIElementGetTypeID() {
            return (focusedRef as! AXUIElement)
        }
        var windowsRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
           let list = windowsRef as? [AXUIElement] {
            return list.first
        }
        return nil
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef else {
            return nil
        }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &origin)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    private func setAXFrame(_ element: AXUIElement, to rect: CGRect) {
        var origin = CGPoint(x: round(rect.origin.x), y: round(rect.origin.y))
        var size = CGSize(width: round(rect.size.width), height: round(rect.size.height))

        // Set size -> position -> size (classic macOS AX trick for apps that clamp position before resize)
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        }
        if let posVal = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    private func axBool(_ element: AXUIElement, _ attr: String) -> Bool? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.boolValue
    }

    private func usableAXVisibleFrame(for screen: NSScreen, settings: WindowSnappingSettings) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let vis = screen.visibleFrame
        let stageInset = CGFloat(max(0, settings.stageManagerMargin))
        return CGRect(
            x: vis.origin.x + stageInset,
            y: primaryHeight - (vis.origin.y + vis.height),
            width: max(300, vis.width - stageInset),
            height: vis.height
        )
    }

    private func cocoaPointToAX(_ pt: NSPoint) -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: pt.x, y: primaryHeight - pt.y)
    }

    private func axRectToCocoa(_ rect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(
            x: rect.origin.x,
            y: primaryHeight - (rect.origin.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    private func screen(forAXRect axRect: CGRect) -> NSScreen? {
        guard !axRect.isEmpty else { return NSScreen.main }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaCenter = CGPoint(x: axRect.midX, y: primaryHeight - axRect.midY)
        return NSScreen.screens.first { $0.frame.contains(cocoaCenter) } ?? NSScreen.main
    }
}
