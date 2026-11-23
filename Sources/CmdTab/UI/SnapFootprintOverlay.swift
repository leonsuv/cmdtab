import AppKit
import SwiftUI

/// Translucent rounded preview overlay showing the target window rectangle
/// when dragging a window to a screen edge or corner ("Fußabdruck").
@MainActor
final class SnapFootprintOverlay {
    static let shared = SnapFootprintOverlay()

    private var panel: NSPanel?
    private var isVisible = false

    private init() {}

    func show(cocoaRect: NSRect, animated: Bool) {
        let insetRect = cocoaRect.insetBy(dx: 4, dy: 4)
        guard insetRect.width > 20 && insetRect.height > 20 else {
            hide()
            return
        }

        if panel == nil {
            let p = NSPanel(
                contentRect: insetRect,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.animationBehavior = .none

            let host = NSHostingView(rootView: SnapFootprintView())
            host.frame = NSRect(origin: .zero, size: insetRect.size)
            host.autoresizingMask = [.width, .height]
            p.contentView = host
            self.panel = p
        }

        guard let panel else { return }

        if !isVisible {
            panel.alphaValue = 0
            panel.setFrame(insetRect, display: true)
            panel.orderFrontRegardless()
            isVisible = true

            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.14
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    panel.animator().alphaValue = 1
                }
            } else {
                panel.alphaValue = 1
            }
        } else {
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.14
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(insetRect, display: true)
                }
            } else {
                panel.setFrame(insetRect, display: true)
            }
        }
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        panel?.orderOut(nil)
    }
}

private struct SnapFootprintView: View {
    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow)
                .opacity(0.65)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.75), lineWidth: 2.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
    }
}
