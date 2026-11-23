import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case controls
    case snapping
    case general
    case exceptions
    case extras

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .controls: return "command"
        case .snapping: return "rectangle.split.2x2"
        case .general: return "gearshape"
        case .exceptions: return "hand.raised"
        case .extras: return "sparkles"
        }
    }

    @MainActor
    var title: String {
        switch self {
        case .appearance: return L10n.t("Darstellung", "Appearance")
        case .controls: return L10n.t("Steuerung", "Controls")
        case .snapping: return L10n.t("Fenster-Snapping", "Window Snapping")
        case .general: return L10n.t("Allgemein", "General")
        case .exceptions: return L10n.t("Ausnahmen", "Exceptions")
        case .extras: return L10n.t("Extras & Tipps", "Extras & Tips")
        }
    }
}

@MainActor
final class SettingsUIState: ObservableObject {
    static let shared = SettingsUIState()

    @Published var selectedSection: SettingsSection = .appearance
    @Published var sidebarSearch: String = ""
    @Published var selectedShortcutID: UUID?
    @Published var shortcutSubTab: Int = 0
    @Published var selectedExceptionID: UUID?
    @Published var statusMessage: String?

    let modifierRecorderState = KeyRecorderState()
    let triggerKeyRecorderState = KeyRecorderState()
}

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var ui = SettingsUIState.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailContent
        }
        .frame(minWidth: 860, minHeight: 580)
        .onAppear {
            if ui.selectedShortcutID == nil {
                ui.selectedShortcutID = settings.payload.shortcuts.first?.id
            }
            if ui.selectedExceptionID == nil {
                ui.selectedExceptionID = settings.payload.exceptions.first?.id
            }
            permissions.refresh()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                TextField(L10n.t("Suche", "Search"), text: $ui.sidebarSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
            .padding(.top, 36)

            VStack(spacing: 4) {
                ForEach(filteredSections) { section in
                    Button {
                        ui.selectedSection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 20)
                            Text(section.title)
                                .font(.system(size: 13, weight: ui.selectedSection == section ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(ui.selectedSection == section ? Color.accentColor.opacity(0.22) : Color.clear)
                        )
                        .foregroundStyle(ui.selectedSection == section ? Color.accentColor : Color.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            VStack(spacing: 8) {
                Button {
                    SwitcherPanelController.shared.showManually(openSearch: false)
                } label: {
                    Label(L10n.t("Wechsler testen", "Test Switcher"), systemImage: "macwindow.on.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(LinearGradient(colors: [Color.accentColor, Color.purple.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                        )
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text(L10n.t("CmdTab beenden", "Quit CmdTab"))
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .frame(width: 200)
        .background(VisualEffectBackground(material: .sidebar, blendingMode: .behindWindow))
    }

    private var filteredSections: [SettingsSection] {
        let q = ui.sidebarSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return SettingsSection.allCases }
        return SettingsSection.allCases.filter { $0.title.lowercased().contains(q) }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PermissionsBannerView()

                if let statusMessage = ui.statusMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(statusMessage)
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button("✕") { ui.statusMessage = nil }
                            .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.12)))
                }

                switch ui.selectedSection {
                case .appearance:
                    appearanceSection
                case .controls:
                    controlsSection
                case .snapping:
                    SnappingSettingsView()
                case .general:
                    generalSection
                case .exceptions:
                    exceptionsSection
                case .extras:
                    extrasSection
                }
            }
            .padding(24)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 1. Darstellung (Appearance)

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.t("Darstellung", "Appearance"),
                subtitle: L10n.t("Wechsle zwischen 3 verschiedenen Stilen und passe Größe, Design und Vorschau an.", "Switch between 3 visual styles and customize size, theme, and live preview.")
            )

            // 3 Visual Style Cards
            HStack(spacing: 14) {
                styleCard(style: .thumbnails, label: L10n.styleName(.thumbnails)) {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(i == 1 ? 0.95 : 0.7))
                                .frame(height: 46)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(i == 1 ? Color.accentColor : Color.clear, lineWidth: 2)
                                )
                        }
                    }
                    .padding(10)
                }

                styleCard(style: .appIcons, label: L10n.styleName(.appIcons)) {
                    HStack(spacing: 8) {
                        ForEach(["safari", "folder", "note.text"], id: \.self) { sym in
                            Image(systemName: sym)
                                .font(.system(size: 18))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.85)))
                        }
                    }
                    .padding(10)
                }

                styleCard(style: .titles, label: L10n.styleName(.titles)) {
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { i in
                            HStack(spacing: 5) {
                                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.85)).frame(height: 7)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4).fill(i == 0 ? Color.accentColor.opacity(0.45) : Color.black.opacity(0.25)))
                        }
                    }
                    .padding(10)
                }
            }

            settingsCard {
                labeledRow(L10n.t("Größe", "Size")) {
                    Picker("", selection: $settings.payload.size) {
                        ForEach(SwitcherSize.allCases) { sz in
                            Text(L10n.sizeName(sz)).tag(sz)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                Divider()

                labeledRow(L10n.t("Erscheinungsbild", "Theme")) {
                    Picker("", selection: $settings.payload.appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(L10n.appearanceName(mode)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Divider()

                labeledRow(L10n.t("Nach Loslassen der Tasten", "After releasing keys")) {
                    Picker("", selection: $settings.payload.releaseBehavior) {
                        ForEach(ReleaseBehavior.allCases) { beh in
                            Text(L10n.releaseName(beh)).tag(beh)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Divider()

                Toggle(L10n.t("Große Fenster-Vorschau hinter dem Wechsler anzeigen", "Show large window preview behind switcher"), isOn: $settings.payload.showLivePreview)
                Divider()
                Toggle(L10n.t("Status-Badges anzeigen (Space, Minimiert, Ausgeblendet)", "Show status badges (Space, Minimized, Hidden)"), isOn: $settings.payload.showStatusBadges)
            }

            settingsCard {
                labeledRow(L10n.t("Anzeigen auf Bildschirm", "Show on screen")) {
                    Picker("", selection: $settings.payload.displayScreen) {
                        ForEach(ScreenDisplayMode.allCases) { mode in
                            Text(L10n.screenDisplayName(mode)).tag(mode)
                        }
                    }
                    .frame(width: 220)
                }
            }
        }
    }

    private func styleCard<Preview: View>(style: SwitcherStyle, label: String, @ViewBuilder preview: () -> Preview) -> some View {
        let isSelected = settings.payload.style == style
        return Button {
            settings.payload.style = style
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.65), Color.blue.opacity(0.55), Color.teal.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    preview()
                }
                .frame(height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 3 : 1)
                )

                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Steuerung (Controls / Shortcuts)

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L10n.t("Steuerung", "Controls"),
                subtitle: L10n.t("Konfiguriere mehrere Tastenkürzel mit eigenen Filtern, Sortierungen und Stilen (auch ⌘+Tab).", "Configure multiple shortcuts with independent filters, sorting, and styles (including ⌘+Tab).")
            )

            HStack(alignment: .top, spacing: 14) {
                // Left list of shortcuts
                VStack(spacing: 6) {
                    ForEach(settings.payload.shortcuts) { sc in
                        let isSel = sc.id == ui.selectedShortcutID
                        Button {
                            ui.selectedShortcutID = sc.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sc.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(sc.shortcutLabel)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(isSel ? .white.opacity(0.85) : .secondary)
                                }
                                Spacer()
                                if !sc.isEnabled {
                                    Image(systemName: "pause.circle")
                                        .font(.system(size: 11))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSel ? Color.accentColor : Color.primary.opacity(0.05))
                            )
                            .foregroundStyle(isSel ? .white : .primary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 10)

                    HStack(spacing: 6) {
                        Button {
                            let newSC = ShortcutConfig(
                                name: "\(L10n.t("Tastenkürzel", "Shortcut")) \(settings.payload.shortcuts.count + 1)",
                                holdModifiers: [.command],
                                triggerKeyCode: UInt16(kVK_Tab)
                            )
                            settings.payload.shortcuts.append(newSC)
                            ui.selectedShortcutID = newSC.id
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if let id = ui.selectedShortcutID, settings.payload.shortcuts.count > 1 {
                                settings.payload.shortcuts.removeAll { $0.id == id }
                                ui.selectedShortcutID = settings.payload.shortcuts.first?.id
                            }
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .disabled(settings.payload.shortcuts.count <= 1)

                        Spacer()
                    }
                }
                .frame(width: 175)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
                )

                // Right shortcut editor
                if let idx = settings.payload.shortcuts.firstIndex(where: { $0.id == ui.selectedShortcutID }) {
                    shortcutEditor(binding: $settings.payload.shortcuts[idx])
                }
            }
        }
    }

    private func shortcutEditor(binding: Binding<ShortcutConfig>) -> some View {
        settingsCard {
            HStack {
                TextField(L10n.t("Name", "Name"), text: binding.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
                Spacer()
                Toggle(L10n.t("Aktiv", "Enabled"), isOn: binding.isEnabled)
                    .toggleStyle(.switch)
            }

            Divider()

            HStack(spacing: 8) {
                Text(L10n.t("Auslöser:", "Trigger:"))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(L10n.t("Halten", "Hold"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    ModifierPickerButton(modifiers: binding.holdModifiers, state: ui.modifierRecorderState)
                    Text(L10n.t("und drücken", "and press"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    TriggerKeyRecorderButton(keyCode: binding.triggerKeyCode, state: ui.triggerKeyRecorderState)
                }
            }

            Picker("", selection: $ui.shortcutSubTab) {
                Text(L10n.t("Filtern", "Filter")).tag(0)
                Text(L10n.t("Darstellung", "Display")).tag(1)
                Text(L10n.t("Sortierung & Gruppierung", "Sort & Group")).tag(2)
            }
            .pickerStyle(.segmented)

            if ui.shortcutSubTab == 0 {
                VStack(spacing: 10) {
                    labeledRow(L10n.t("Fenster von Apps anzeigen", "Show windows from apps")) {
                        Picker("", selection: binding.appFilter) {
                            ForEach(AppFilterMode.allCases) { m in Text(L10n.appFilterName(m)).tag(m) }
                        }.frame(width: 185)
                    }
                    labeledRow(L10n.t("Fenster von Spaces anzeigen", "Show windows from Spaces")) {
                        Picker("", selection: binding.spaceFilter) {
                            ForEach(SpaceFilterMode.allCases) { m in Text(L10n.spaceFilterName(m)).tag(m) }
                        }.frame(width: 185)
                    }
                    labeledRow(L10n.t("Fenster von Bildschirmen anzeigen", "Show windows from screens")) {
                        Picker("", selection: binding.screenFilter) {
                            ForEach(ScreenFilterMode.allCases) { m in Text(L10n.screenFilterName(m)).tag(m) }
                        }.frame(width: 185)
                    }
                    Divider()
                    labeledRow(L10n.t("Minimierte Fenster anzeigen", "Show minimized windows")) {
                        Picker("", selection: binding.showMinimized) {
                            ForEach(VisibilityFilter.allCases) { v in Text(L10n.visibilityName(v)).tag(v) }
                        }.frame(width: 185)
                    }
                    labeledRow(L10n.t("Ausgeblendete Fenster anzeigen", "Show hidden windows")) {
                        Picker("", selection: binding.showHidden) {
                            ForEach(VisibilityFilter.allCases) { v in Text(L10n.visibilityName(v)).tag(v) }
                        }.frame(width: 185)
                    }
                    labeledRow(L10n.t("Vollbildfenster anzeigen", "Show fullscreen windows")) {
                        Picker("", selection: binding.showFullscreen) {
                            ForEach(VisibilityFilter.allCases) { v in Text(L10n.visibilityName(v)).tag(v) }
                        }.frame(width: 185)
                    }
                    labeledRow(L10n.t("Apps ohne geöffnetes Fenster", "Apps with no open window")) {
                        Picker("", selection: binding.showWindowlessApps) {
                            ForEach(VisibilityFilter.allCases) { v in Text(L10n.visibilityName(v)).tag(v) }
                        }.frame(width: 185)
                    }
                }
            } else if ui.shortcutSubTab == 1 {
                VStack(spacing: 10) {
                    labeledRow(L10n.t("Stil-Überschreibung", "Style override")) {
                        Picker("", selection: binding.styleOverride) {
                            Text(L10n.t("Standard (Global)", "Default (Global)")).tag(SwitcherStyle?.none)
                            ForEach(SwitcherStyle.allCases) { st in
                                Text(L10n.styleName(st)).tag(SwitcherStyle?.some(st))
                            }
                        }.frame(width: 185)
                    }
                    labeledRow(L10n.t("Nach Loslassen der Tasten", "After releasing keys")) {
                        Picker("", selection: binding.releaseBehaviorOverride) {
                            Text(L10n.t("Standard (Global)", "Default (Global)")).tag(ReleaseBehavior?.none)
                            ForEach(ReleaseBehavior.allCases) { b in
                                Text(L10n.releaseName(b)).tag(ReleaseBehavior?.some(b))
                            }
                        }.frame(width: 185)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    labeledRow(L10n.t("Sortierung", "Sort order")) {
                        Picker("", selection: binding.sortOrder) {
                            ForEach(SortOrder.allCases) { s in Text(L10n.sortOrderName(s)).tag(s) }
                        }.frame(width: 185)
                    }
                    Toggle(L10n.t("Fenster nach App gruppieren", "Group windows by app"), isOn: binding.groupByApp)
                }
            }
        }
    }

    // MARK: - 3. Allgemein (General)

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.t("Allgemein", "General"),
                subtitle: L10n.t("Startverhalten, Menüleiste, Sprache und Einstellungen sichern.", "Startup behavior, menu bar, language, and settings backup.")
            )

            settingsCard {
                Toggle(L10n.t("Beim Anmelden starten", "Launch at login"), isOn: $settings.payload.launchAtLogin)
                Divider()
                Toggle(L10n.t("Menüleistensymbol anzeigen", "Show menu bar icon"), isOn: $settings.payload.showMenuBarIcon)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(L10n.t("Fenster im Hintergrund erfassen", "Capture windows in background"), isOn: $settings.payload.backgroundCapture)
                    Text(L10n.t(
                        "Wenn deaktiviert, werden Miniaturen erst beim Öffnen des Wechslers aktualisiert (spart Energie und vermeidet dauerhafte Bildschirmaufnahme).",
                        "When disabled, thumbnails refresh only when opening the switcher (saves battery and avoids continuous capture)."
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Divider()
                labeledRow(L10n.t("Sprache", "Language")) {
                    Picker("", selection: $settings.payload.language) {
                        Text(L10n.t("Systemstandard", "System Default")).tag(AppLanguage.system)
                        Divider()
                        ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    }
                    .frame(width: 190)
                }
            }

            HStack(spacing: 10) {
                Button(L10n.t("Einstellungen exportieren…", "Export Settings…")) {
                    exportSettings()
                }
                Button(L10n.t("Einstellungen importieren…", "Import Settings…")) {
                    importSettings()
                }
                Spacer()
                Button(L10n.t("Zurücksetzen", "Reset Defaults"), role: .destructive) {
                    settings.resetToDefaults()
                    ui.statusMessage = L10n.t("Einstellungen wurden zurückgesetzt.", "Settings reset to defaults.")
                }
            }
        }
    }

    // MARK: - 4. Ausnahmen (Exceptions)

    private var exceptionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(
                title: L10n.t("Ausnahmen", "Exceptions"),
                subtitle: L10n.t("Blende bestimmte Apps im Wechsler aus oder ignoriere Tastenkürzel (z. B. für VMs & Remote Desktop).", "Hide specific apps from the switcher or ignore shortcuts (e.g. for VMs & Remote Desktop).")
            )

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(settings.payload.exceptions) { ex in
                                let isSel = ex.id == ui.selectedExceptionID
                                Button {
                                    ui.selectedExceptionID = ex.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(nsImage: appIcon(for: ex.bundleIdentifier))
                                            .resizable()
                                            .frame(width: 24, height: 24)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(ex.displayName)
                                                .font(.system(size: 12, weight: .semibold))
                                                .lineLimit(1)
                                            Text(exceptionSummary(ex))
                                                .font(.system(size: 10))
                                                .foregroundStyle(isSel ? .white.opacity(0.85) : .secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSel ? Color.accentColor : Color.clear)
                                    )
                                    .foregroundStyle(isSel ? .white : .primary)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 280)

                    HStack(spacing: 6) {
                        Button {
                            pickAppForException()
                        } label: {
                            Image(systemName: "plus").frame(width: 26, height: 24)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            if let id = ui.selectedExceptionID {
                                settings.payload.exceptions.removeAll { $0.id == id }
                                ui.selectedExceptionID = settings.payload.exceptions.first?.id
                            }
                        } label: {
                            Image(systemName: "minus").frame(width: 26, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ui.selectedExceptionID == nil)

                        Spacer()
                    }
                }
                .frame(width: 210)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)))
                )

                if let idx = settings.payload.exceptions.firstIndex(where: { $0.id == ui.selectedExceptionID }) {
                    let binding = $settings.payload.exceptions[idx]
                    settingsCard {
                        HStack(spacing: 10) {
                            Image(nsImage: appIcon(for: binding.wrappedValue.bundleIdentifier))
                                .resizable()
                                .frame(width: 34, height: 34)
                            TextField("Name", text: binding.displayName)
                                .textFieldStyle(.roundedBorder)
                        }
                        Divider()
                        labeledRow("Bundle ID") {
                            TextField("com.example.app", text: binding.bundleIdentifier)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                        labeledRow(L10n.t("Fenster ausblenden", "Hide windows")) {
                            Picker("", selection: binding.hideWindows) {
                                ForEach(ExceptionHideRule.allCases) { r in Text(L10n.hideRuleName(r)).tag(r) }
                            }.frame(width: 220)
                        }
                        labeledRow(L10n.t("Tastenkürzel ignorieren", "Ignore shortcuts")) {
                            Picker("", selection: binding.ignoreShortcuts) {
                                ForEach(ExceptionIgnoreShortcutRule.allCases) { r in Text(L10n.ignoreShortcutRuleName(r)).tag(r) }
                            }.frame(width: 220)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 5. Extras & Power Features

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(
                title: L10n.t("CmdTab Extras", "CmdTab Extras"),
                subtitle: L10n.t("Zusätzliche Power-Features exklusiv in CmdTab für noch schnelleres Arbeiten.", "Extra power features built into CmdTab for even faster window management.")
            )

            settingsCard {
                Toggle(L10n.t("Schnellwahl-Nummern (1–9) anzeigen", "Show Quick-Jump numbers (1–9)"), isOn: $settings.payload.showQuickJumpNumbers)
                Divider()
                Toggle(L10n.t("Hover-Aktionsleiste auf Miniaturen (Schließen, Minimieren, Vollbild, Pin)", "Show hover action buttons on thumbnails (Close, Minimize, Fullscreen, Pin)"), isOn: $settings.payload.showHoverWindowActions)
                Divider()
                Toggle(L10n.t("Fenster-Andocken (Tiling: Links / Rechts / Maximieren) aktivieren", "Enable Window Snapping (Left / Right / Maximize)"), isOn: $settings.payload.showWindowSnappingActions)
            }

            settingsCard {
                Text(L10n.t("Tastatur-Kommandos bei geöffnetem Wechsler", "Keyboard commands while switcher is open"))
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 6) {
                    cheatRow("1 – 9", L10n.t("Sofort zum Fenster 1–9 springen", "Jump directly to window 1–9"))
                    cheatRow("Space / /", L10n.t("Live-Suche (Fuzzy-Filter) ein-/ausschalten", "Toggle live fuzzy search"))
                    cheatRow("W", L10n.t("Ausgewähltes Fenster schließen", "Close selected window"))
                    cheatRow("Q", L10n.t("App des ausgewählten Fensters beenden", "Quit app of selected window"))
                    cheatRow("M", L10n.t("Fenster minimieren / wiederherstellen", "Minimize / restore window"))
                    cheatRow("H", L10n.t("App ausblenden / einblenden", "Hide / unhide app"))
                    cheatRow("F", L10n.t("Vollbildmodus umschalten", "Toggle fullscreen"))
                    cheatRow("P", L10n.t("Fenster oben anpinnen (Favorit)", "Pin window to the front (Favorite)"))
                    cheatRow("[  /  ]  /  \\", L10n.t("Fenster links / rechts andocken oder maximieren", "Snap window left / right or maximize"))
                    cheatRow("↑ ↓ ← →", L10n.t("Im Raster oder der Liste navigieren", "Navigate grid or list"))
                    cheatRow("Esc", L10n.t("Wechsler schließen ohne zu wechseln", "Cancel without switching"))
                }
            }

            if !settings.payload.pinnedWindowKeys.isEmpty {
                settingsCard {
                    HStack {
                        Text("\(L10n.t("Angepinnte Fenster", "Pinned windows")) (\(settings.payload.pinnedWindowKeys.count))")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button(L10n.t("Alle lösen", "Unpin all")) {
                            settings.payload.pinnedWindowKeys.removeAll()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func labeledRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            control()
        }
    }

    private func cheatRow(_ keys: String, _ desc: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.1)))
                .frame(width: 96, alignment: .leading)
            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func exceptionSummary(_ ex: AppException) -> String {
        if ex.ignoreShortcuts != .never {
            return L10n.t("Tastenkürzel ignorieren", "Ignore shortcuts")
        }
        if ex.hideWindows != .never {
            return L10n.t("Ausblenden", "Hide")
        }
        return L10n.t("Aktiv", "Active")
    }

    private func appIcon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func pickAppForException() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier {
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let newEx = AppException(bundleIdentifier: bid, displayName: name, hideWindows: .always, ignoreShortcuts: .never)
            settings.payload.exceptions.append(newEx)
            ui.selectedExceptionID = newEx.id
        }
    }

    private func exportSettings() {
        guard let data = settings.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "cmdtab-settings.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
            ui.statusMessage = L10n.t("Einstellungen exportiert.", "Settings exported.")
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            do {
                try settings.importJSON(data)
                ui.statusMessage = L10n.t("Einstellungen erfolgreich importiert.", "Settings imported successfully.")
            } catch {
                ui.statusMessage = L10n.t("Import fehlgeschlagen: ungültige Datei.", "Import failed: invalid JSON file.")
            }
        }
    }
}
