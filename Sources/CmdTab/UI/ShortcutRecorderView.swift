import AppKit
import SwiftUI

@MainActor
final class KeyRecorderState: ObservableObject {
    @Published var isRecording = false
    var monitor: Any?

    func stop() {
        isRecording = false
        HotkeyManager.shared.isPausedForRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

struct ModifierPickerButton: View {
    @Binding var modifiers: ModifierFlags
    @ObservedObject private var state: KeyRecorderState

    init(modifiers: Binding<ModifierFlags>, state: KeyRecorderState) {
        self._modifiers = modifiers
        self.state = state
    }

    var body: some View {
        Button {
            if state.isRecording {
                state.stop()
            } else {
                startRecording()
            }
        } label: {
            Text(state.isRecording ? L10n.t("Modifier drücken…", "Press modifier…") : (modifiers.isEmpty ? "—" : modifiers.displaySymbols))
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 74)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(state.isRecording ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(state.isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onDisappear { state.stop() }
    }

    private func startRecording() {
        state.isRecording = true
        HotkeyManager.shared.isPausedForRecording = true
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown && event.keyCode == 53 { // Escape
                state.stop()
                return nil
            }
            let captured = ModifierFlags.from(nsFlags: event.modifierFlags)
            if !captured.isEmpty {
                modifiers = captured
                state.stop()
                return nil
            }
            return event
        }
    }
}

struct TriggerKeyRecorderButton: View {
    @Binding var keyCode: UInt16
    @ObservedObject private var state: KeyRecorderState

    init(keyCode: Binding<UInt16>, state: KeyRecorderState) {
        self._keyCode = keyCode
        self.state = state
    }

    var body: some View {
        Button {
            if state.isRecording {
                state.stop()
            } else {
                startRecording()
            }
        } label: {
            Text(state.isRecording ? L10n.t("Taste drücken…", "Press key…") : KeyCodeTranslator.symbol(for: keyCode))
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 74)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(state.isRecording ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(state.isRecording ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .onDisappear { state.stop() }
    }

    private func startRecording() {
        state.isRecording = true
        HotkeyManager.shared.isPausedForRecording = true
        state.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { // Escape cancels
                state.stop()
                return nil
            }
            keyCode = event.keyCode
            state.stop()
            return nil
        }
    }
}
