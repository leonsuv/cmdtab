import AppKit
import SwiftUI

@MainActor
final class SnappingUIState: ObservableObject {
    static let shared = SnappingUIState()

    @Published var selectedTab: Int = 0
    @Published var recordingAction: SnapAction? = nil
    var monitor: Any?

    func startRecording(for action: SnapAction) {
        stopRecording()
        recordingAction = action
        HotkeyManager.shared.isPausedForRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape cancels
                self.stopRecording()
                return nil
            }
            let mods = ModifierFlags.from(nsFlags: event.modifierFlags)
            guard !mods.isEmpty else { return nil }
            let combo = SnapKeyCombo(modifiers: mods, keyCode: event.keyCode)
            AppSettings.shared.payload.snapping.setShortcut(combo, for: action)
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        recordingAction = nil
        HotkeyManager.shared.isPausedForRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct SnappingSettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var ui = SnappingUIState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("Fenster-Snapping", "Window Snapping"))
                        .font(.system(size: 22, weight: .bold))
                    Text(L10n.t(
                        "Ordne Fenster blitzschnell per Tastaturkurzbefehl oder Ziehen an den Bildschirmrand an.",
                        "Snap and tile windows instantly with global keyboard shortcuts or by dragging to screen edges."
                    ))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(L10n.t("Aktiv", "Enabled"), isOn: $settings.payload.snapping.isEnabled)
                    .toggleStyle(.switch)
            }

            Picker("", selection: $ui.selectedTab) {
                Text(L10n.t("Tastaturkurzbefehle", "Keyboard Shortcuts")).tag(0)
                Text(L10n.t("Schnappbereiche", "Snap Areas")).tag(1)
                Text(L10n.t("Einstellungen", "Settings")).tag(2)
            }
            .pickerStyle(.segmented)

            Group {
                if ui.selectedTab == 0 {
                    shortcutsTab
                } else if ui.selectedTab == 1 {
                    snapAreasTab
                } else {
                    snappingOptionsTab
                }
            }
            .disabled(!settings.payload.snapping.isEnabled)
            .opacity(settings.payload.snapping.isEnabled ? 1.0 : 0.5)
        }
        .onDisappear { ui.stopRecording() }
    }

    // MARK: - Tab 1: Keyboard Shortcuts (2-column Rectangle layout)

    private var shortcutsTab: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ForEach(SnapAction.leftColumnActions) { action in
                    shortcutRow(for: action)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                ForEach(SnapAction.rightColumnActions) { action in
                    shortcutRow(for: action)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func shortcutRow(for action: SnapAction) -> some View {
        let combo = settings.payload.snapping.shortcut(for: action)
        let isRec = ui.recordingAction == action

        return HStack(spacing: 8) {
            Text(action.localizedName)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)

            SnapMiniIcon(action: action)
                .frame(width: 24, height: 16)

            HStack(spacing: 0) {
                Button {
                    if isRec {
                        ui.stopRecording()
                    } else {
                        ui.startRecording(for: action)
                    }
                } label: {
                    Text(isRec
                         ? L10n.t("Drücken…", "Press…")
                         : (combo?.displayLabel ?? L10n.t("Kurzbefehl aufnehmen", "Record Shortcut")))
                        .font(.system(size: 11, weight: combo != nil || isRec ? .semibold : .regular))
                        .foregroundStyle(isRec ? Color.accentColor : (combo != nil ? .primary : .secondary))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if combo != nil {
                    Divider().frame(height: 14)
                    Button {
                        settings.payload.snapping.setShortcut(nil, for: action)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 142, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRec ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isRec ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Tab 2: Snap Areas (Drag to Screen Edges)

    private var snapAreasTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(L10n.t("Fenster zum Anordnen an Bildschirmrand ziehen", "Snap windows by dragging to screen edges"), isOn: $settings.payload.snapping.dragToSnapEnabled)
                    Toggle(L10n.t("Fenster beim Bewegen auf Originalgröße zurücksetzen", "Unsnap & restore original size when dragging away"), isOn: $settings.payload.snapping.restoreOnDrag)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(L10n.t("Haptisches Feedback", "Haptic feedback"), isOn: $settings.payload.snapping.hapticFeedback)
                    Toggle(L10n.t("Fußabdruck animieren", "Animate footprint preview"), isOn: $settings.payload.snapping.animateFootprint)
                }
            }

            Divider()

            // Visual Monitor Diagram surrounded by 8 edge/corner pickers
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    zonePicker(.topLeft)
                    zonePicker(.top)
                    zonePicker(.topRight)
                }

                HStack(spacing: 14) {
                    zonePicker(.left)

                    ZStack {
                        LinearGradient(
                            colors: [
                                Color(red: 0.16, green: 0.42, blue: 0.78),
                                Color(red: 0.25, green: 0.56, blue: 0.88),
                                Color(red: 0.12, green: 0.26, blue: 0.52)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .frame(height: 130)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.28), lineWidth: 2)
                    )

                    zonePicker(.right)
                }

                HStack(spacing: 14) {
                    zonePicker(.bottomLeft)
                    zonePicker(.bottom)
                    zonePicker(.bottomRight)
                }
            }
            .disabled(!settings.payload.snapping.dragToSnapEnabled)
            .opacity(settings.payload.snapping.dragToSnapEnabled ? 1.0 : 0.45)
        }
        .padding(18)
        .background(cardBackground)
    }

    private func zonePicker(_ zone: SnapEdgeZone) -> some View {
        let binding = Binding<SnapAction>(
            get: { settings.payload.snapping.action(for: zone) },
            set: { settings.payload.snapping.setAction($0, for: zone) }
        )
        return Picker("", selection: binding) {
            ForEach(SnapAction.snapZoneChoices) { action in
                Text(action.localizedName).tag(action)
            }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tab 3: Snapping Settings

    private var snappingOptionsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(L10n.t("Wiederholte Befehle", "Repeated commands"))
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Picker("", selection: $settings.payload.snapping.repeatedCommandBehavior) {
                        ForEach(RepeatedSnapBehavior.allCases) { beh in
                            Text(beh.localizedName).tag(beh)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 280)
                }

                Divider()

                HStack(spacing: 12) {
                    Text(L10n.t("Abstände zwischen Fenstern", "Gaps between windows"))
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Slider(value: $settings.payload.snapping.windowGap, in: 0...32, step: 2)
                    Text("\(Int(settings.payload.snapping.windowGap)) px")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Divider()

                Toggle(L10n.t("Mauszeiger zusammen mit dem Fenster über Bildschirme bewegen", "Move cursor along with window across displays"), isOn: $settings.payload.snapping.moveCursorAcrossScreens)

                Divider()

                Toggle(L10n.t("Doppelklick auf die Titelleiste zum Maximieren/Wiederherstellen", "Double-click window titlebar to maximize/restore"), isOn: $settings.payload.snapping.doubleClickTitleBarToMaximize)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text(L10n.t("Stage Manager Bereich (linker Rand)", "Stage Manager margin (left edge)"))
                            .font(.system(size: 13))
                            .lineLimit(1)
                        Slider(value: $settings.payload.snapping.stageManagerMargin, in: 0...240, step: 10)
                        Text("\(Int(settings.payload.snapping.stageManagerMargin)) px")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    Text(L10n.t(
                        "Lässt links Platz für Stage Manager, wenn > 0 px eingestellt ist.",
                        "Reserves space on the left edge for Stage Manager when set above 0 px."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(cardBackground)

            HStack {
                Button(L10n.t("Standard-Tastaturkurzbefehle wiederherstellen", "Restore Default Shortcuts")) {
                    settings.payload.snapping.shortcuts = WindowSnappingSettings.defaultShortcuts()
                    settings.payload.snapping.edgeZones = WindowSnappingSettings.defaultEdgeZones()
                }
                Spacer()
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - Mini Window Layout Icon (like Rectangle)

private struct SnapMiniIcon: View {
    let action: SnapAction

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    )

                if let rect = fillRect(w: w, h: h) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.65))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                } else if let symbol = symbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .frame(width: w, height: h)
                }
            }
        }
    }

    private var symbolName: String? {
        switch action {
        case .smaller: return "minus"
        case .larger: return "plus"
        case .restore: return "arrow.uturn.backward"
        case .nextDisplay: return "chevron.right"
        case .previousDisplay: return "chevron.left"
        default: return nil
        }
    }

    private func fillRect(w: CGFloat, h: CGFloat) -> CGRect? {
        let p: CGFloat = 2
        let iw = w - p * 2
        let ih = h - p * 2
        switch action {
        case .leftHalf:       return CGRect(x: p, y: p, width: iw / 2, height: ih)
        case .rightHalf:      return CGRect(x: p + iw / 2, y: p, width: iw / 2, height: ih)
        case .centerHalf:     return CGRect(x: p + iw * 0.25, y: p, width: iw * 0.5, height: ih)
        case .topHalf:        return CGRect(x: p, y: p, width: iw, height: ih / 2)
        case .bottomHalf:     return CGRect(x: p, y: p + ih / 2, width: iw, height: ih / 2)
        case .topLeft:        return CGRect(x: p, y: p, width: iw / 2, height: ih / 2)
        case .topRight:       return CGRect(x: p + iw / 2, y: p, width: iw / 2, height: ih / 2)
        case .bottomLeft:     return CGRect(x: p, y: p + ih / 2, width: iw / 2, height: ih / 2)
        case .bottomRight:    return CGRect(x: p + iw / 2, y: p + ih / 2, width: iw / 2, height: ih / 2)
        case .firstThird:     return CGRect(x: p, y: p, width: iw / 3, height: ih)
        case .centerThird:    return CGRect(x: p + iw / 3, y: p, width: iw / 3, height: ih)
        case .lastThird:      return CGRect(x: p + iw * 2 / 3, y: p, width: iw / 3, height: ih)
        case .firstTwoThirds: return CGRect(x: p, y: p, width: iw * 2 / 3, height: ih)
        case .lastTwoThirds:  return CGRect(x: p + iw / 3, y: p, width: iw * 2 / 3, height: ih)
        case .maximize:       return CGRect(x: p, y: p, width: iw, height: ih)
        case .almostMaximize: return CGRect(x: p + 2, y: p + 1.5, width: iw - 4, height: ih - 3)
        case .maximizeHeight: return CGRect(x: p + iw * 0.3, y: p, width: iw * 0.4, height: ih)
        case .center:         return CGRect(x: p + iw * 0.22, y: p + ih * 0.22, width: iw * 0.56, height: ih * 0.56)
        default:              return nil
        }
    }
}
