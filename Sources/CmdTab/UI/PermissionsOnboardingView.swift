import SwiftUI

struct PermissionsBannerView: View {
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var hotkeys = HotkeyManager.shared

    var body: some View {
        if !permissions.hasAccessibility || !permissions.hasScreenRecording || !hotkeys.isRunning {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.orange)
                    Text(L10n.t("Systemstatus & Berechtigungen", "System Status & Permissions"))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(L10n.t("Aktualisieren", "Refresh")) {
                        permissions.refresh()
                        if permissions.hasAccessibility {
                            _ = HotkeyManager.shared.start()
                        }
                    }
                    .controlSize(.small)

                    Button(L10n.t("Neu starten", "Relaunch")) {
                        AppDelegate.relaunchApp()
                    }
                    .controlSize(.small)
                }

                if permissions.hasAccessibility && !hotkeys.isRunning {
                    permissionRow(
                        title: L10n.t("Tastenkürzel-Engine nicht aktiv", "Shortcut Engine Inactive"),
                        subtitle: L10n.t(
                            "Bedienungshilfen wurden erkannt — klicke auf Starten (oder starte CmdTab nach der Freigabe einmal neu).",
                            "Accessibility is granted — click Start (or relaunch CmdTab once after granting)."
                        ),
                        granted: false,
                        buttonTitle: L10n.t("Engine starten", "Start Engine"),
                        onRequest: {
                            _ = HotkeyManager.shared.start()
                        }
                    )
                }

                if !permissions.hasAccessibility {
                    permissionRow(
                        title: L10n.t("Bedienungshilfen (Accessibility)", "Accessibility"),
                        subtitle: L10n.t(
                            "Benötigt für globale Tastenkürzel (⌘+Tab / ⌥+Tab) sowie Fensterwechsel, Minimieren, Schließen & Andocken.",
                            "Required for global shortcuts (⌘+Tab / ⌥+Tab) and focusing, minimizing, closing & snapping windows."
                        ),
                        granted: false,
                        buttonTitle: L10n.t("Freigeben…", "Grant…"),
                        onRequest: {
                            permissions.requestAccessibility()
                            permissions.openAccessibilitySettings()
                        }
                    )
                }

                if !permissions.hasScreenRecording {
                    permissionRow(
                        title: L10n.t("Bildschirmaufnahme (Screen Recording)", "Screen Recording"),
                        subtitle: L10n.t(
                            "Benötigt für Live-Miniaturen und die Vollbild-Vorschau vor dem Wechsel.",
                            "Required for live window thumbnails and full-size preview before switching."
                        ),
                        granted: false,
                        buttonTitle: L10n.t("Freigeben…", "Grant…"),
                        onRequest: {
                            permissions.requestScreenRecording()
                            permissions.openScreenRecordingSettings()
                        }
                    )
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                    )
            )
        }
    }

    private func permissionRow(title: String, subtitle: String, granted: Bool, buttonTitle: String, onRequest: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: onRequest)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
