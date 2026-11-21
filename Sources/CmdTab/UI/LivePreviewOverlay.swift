import AppKit
import SwiftUI

/// Displays a full-size live preview of the currently selected window above all other windows,
/// right behind the switcher panel ("Vorschau vor dem Wechsel").
@MainActor
final class LivePreviewOverlay {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<LivePreviewContentView>?
    private var currentTask: Task<Void, Never>?

    func showPreview(for window: WindowInfo, on screen: NSScreen) {
        currentTask?.cancel()

        guard AppSettings.shared.payload.showLivePreview,
              !window.isWindowlessApp,
              window.windowID != 0 else {
            hide()
            return
        }

        let targetFrame = computePreviewFrame(for: window, on: screen)
        let initialImage = window.thumbnail

        present(image: initialImage, window: window, frame: targetFrame)

        currentTask = Task { [weak self] in
            if let hiRes = await ScreenCaptureService.shared.captureFullPreview(for: window.windowID) {
                guard !Task.isCancelled else { return }
                self?.present(image: hiRes, window: window, frame: targetFrame)
            }
        }
    }

    func hide() {
        currentTask?.cancel()
        currentTask = nil
        panel?.orderOut(nil)
    }

    private func present(image: NSImage?, window: WindowInfo, frame: NSRect) {
        guard let image else {
            panel?.orderOut(nil)
            return
        }

        let content = LivePreviewContentView(image: image, windowTitle: window.displayTitle, appName: window.appName)

        if panel == nil {
            let p = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.animationBehavior = .none

            let host = NSHostingView(rootView: content)
            host.frame = NSRect(origin: .zero, size: frame.size)
            host.autoresizingMask = [.width, .height]
            p.contentView = host

            self.panel = p
            self.hostingView = host
        } else {
            hostingView?.rootView = content
        }

        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    private func computePreviewFrame(for window: WindowInfo, on screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame
        let maxW = vis.width * 0.72
        let maxH = vis.height * 0.64

        let aspect: CGFloat
        if window.frame.width > 10 && window.frame.height > 10 {
            aspect = window.frame.width / window.frame.height
        } else if let thumb = window.thumbnail, thumb.size.height > 0 {
            aspect = thumb.size.width / thumb.size.height
        } else {
            aspect = 16.0 / 10.0
        }

        var w = min(maxW, max(480, window.frame.width > 0 ? window.frame.width * 0.85 : maxW * 0.8))
        var h = w / aspect
        if h > maxH {
            h = maxH
            w = h * aspect
        }

        let x = vis.midX - w / 2
        let y = vis.midY - h / 2 + 40
        return NSRect(x: x, y: max(vis.minY + 24, y), width: w, height: h)
    }
}

private struct LivePreviewContentView: View {
    let image: NSImage
    let windowTitle: String
    let appName: String

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2.5)
                )
                .shadow(color: .black.opacity(0.38), radius: 28, y: 12)
                .padding(.top, 14)

            Text(windowTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                )
        }
        .padding(12)
    }
}
