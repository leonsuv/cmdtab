import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService {
    static let shared = ScreenCaptureService()

    private var thumbnailCache: [CGWindowID: NSImage] = [:]
    private var lastCaptureTime: [CGWindowID: Date] = [:]
    private var backgroundTimer: Timer?
    private var isCapturingBatch = false

    private init() {}

    func cachedThumbnail(for windowID: CGWindowID) -> NSImage? {
        thumbnailCache[windowID]
    }

    func pruneCache(keeping activeIDs: Set<CGWindowID>) {
        for key in Array(thumbnailCache.keys) where !activeIDs.contains(key) {
            thumbnailCache.removeValue(forKey: key)
            lastCaptureTime.removeValue(forKey: key)
        }
    }

    func startBackgroundCaptureIfNeeded() {
        stopBackgroundCapture()
        guard AppSettings.shared.payload.backgroundCapture else { return }
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard AppSettings.shared.payload.backgroundCapture else { return }
                guard PermissionsManager.shared.hasScreenRecording else { return }
                await self.refreshAllVisibleWindows(maxCount: 16, thumbnailMaxWidth: 520)
            }
        }
    }

    func stopBackgroundCapture() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    /// Captures fresh thumbnails for the given window IDs asynchronously and invokes `onUpdate` as each arrives.
    func captureThumbnails(
        for windowIDs: [CGWindowID],
        maxWidth: Int = 640,
        forceRefresh: Bool = false,
        onUpdate: @escaping @MainActor (CGWindowID, NSImage) -> Void
    ) {
        guard PermissionsManager.shared.hasScreenRecording else { return }
        guard !windowIDs.isEmpty else { return }

        let now = Date()
        let idsToCapture = windowIDs.filter { id in
            guard id != 0 else { return false }
            if forceRefresh { return true }
            if let last = lastCaptureTime[id], now.timeIntervalSince(last) < 1.5, thumbnailCache[id] != nil {
                return false
            }
            return true
        }

        guard !idsToCapture.isEmpty else { return }

        Task {
            do {
                let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let windowMap = Dictionary(uniqueKeysWithValues: shareable.windows.map { ($0.windowID, $0) })

                await withTaskGroup(of: (CGWindowID, NSImage?).self) { group in
                    for wid in idsToCapture {
                        guard let scWindow = windowMap[wid] else { continue }
                        group.addTask {
                            let image = await Self.captureSingleWindow(scWindow, maxWidth: maxWidth)
                            return (wid, image)
                        }
                    }

                    for await (wid, image) in group {
                        if let image {
                            await MainActor.run {
                                self.thumbnailCache[wid] = image
                                self.lastCaptureTime[wid] = Date()
                                onUpdate(wid, image)
                            }
                        }
                    }
                }
            } catch {
                // ScreenCaptureKit may fail if permission was revoked or window closed mid-capture
            }
        }
    }

    /// Captures a high-resolution image of a single window for the full-size live preview ("Vorschau vor dem Wechsel").
    func captureFullPreview(for windowID: CGWindowID) async -> NSImage? {
        guard windowID != 0, PermissionsManager.shared.hasScreenRecording else {
            return thumbnailCache[windowID]
        }
        do {
            let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let scWindow = shareable.windows.first(where: { $0.windowID == windowID }) else {
                return thumbnailCache[windowID]
            }
            if let img = await Self.captureSingleWindow(scWindow, maxWidth: 1600) {
                return img
            }
        } catch {
            return thumbnailCache[windowID]
        }
        return thumbnailCache[windowID]
    }

    private func refreshAllVisibleWindows(maxCount: Int, thumbnailMaxWidth: Int) async {
        guard !isCapturingBatch else { return }
        isCapturingBatch = true
        defer { isCapturingBatch = false }

        do {
            let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let candidates = shareable.windows.filter { win in
                win.windowLayer == 0 && win.frame.width > 80 && win.frame.height > 80
            }.prefix(maxCount)

            for scWindow in candidates {
                if let image = await Self.captureSingleWindow(scWindow, maxWidth: thumbnailMaxWidth) {
                    thumbnailCache[scWindow.windowID] = image
                    lastCaptureTime[scWindow.windowID] = Date()
                }
            }
        } catch {
            // Ignore transient background errors
        }
    }

    private static func captureSingleWindow(_ scWindow: SCWindow, maxWidth: Int) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let config = SCStreamConfiguration()

        let w = max(scWindow.frame.width, 1)
        let h = max(scWindow.frame.height, 1)
        let scale = min(2.0, Double(maxWidth) / Double(w))
        let targetW = max(64, Int(Double(w) * scale))
        let targetH = max(48, Int(Double(h) * scale))

        config.width = targetW
        config.height = targetH
        config.showsCursor = false
        config.scalesToFit = true
        config.ignoreShadowsSingleWindow = true

        do {
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
        } catch {
            return nil
        }
    }
}
