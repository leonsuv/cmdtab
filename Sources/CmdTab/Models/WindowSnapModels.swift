import Carbon
import Foundation

enum SnapAction: String, Codable, CaseIterable, Identifiable {
    // Halves
    case leftHalf
    case rightHalf
    case centerHalf
    case topHalf
    case bottomHalf

    // Quarters
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    // Thirds
    case firstThird
    case centerThird
    case lastThird
    case firstTwoThirds
    case lastTwoThirds

    // Sizing & Positioning
    case maximize
    case almostMaximize
    case maximizeHeight
    case smaller
    case larger
    case center
    case restore

    // Multi-Display
    case nextDisplay
    case previousDisplay

    // No-op (for disabling an edge zone)
    case none

    var id: String { rawValue }

    /// Actions shown in the left column of the keyboard shortcuts grid
    static var leftColumnActions: [SnapAction] {
        [
            .leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf,
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .firstThird, .centerThird, .lastThird
        ]
    }

    /// Actions shown in the right column of the keyboard shortcuts grid
    static var rightColumnActions: [SnapAction] {
        [
            .maximize, .almostMaximize, .maximizeHeight,
            .smaller, .larger, .center, .restore,
            .nextDisplay, .previousDisplay,
            .firstTwoThirds, .lastTwoThirds
        ]
    }

    /// Actions selectable in edge snap zone pickers
    static var snapZoneChoices: [SnapAction] {
        [
            .none,
            .maximize, .almostMaximize,
            .leftHalf, .rightHalf, .centerHalf, .topHalf, .bottomHalf,
            .topLeft, .topRight, .bottomLeft, .bottomRight,
            .firstThird, .centerThird, .lastThird, .firstTwoThirds, .lastTwoThirds,
            .center
        ]
    }

    @MainActor
    var localizedName: String {
        switch self {
        case .leftHalf: return L10n.t("Linke Hälfte", "Left Half")
        case .rightHalf: return L10n.t("Rechte Hälfte", "Right Half")
        case .centerHalf: return L10n.t("Mittlere Hälfte", "Center Half")
        case .topHalf: return L10n.t("Obere Hälfte", "Top Half")
        case .bottomHalf: return L10n.t("Untere Hälfte", "Bottom Half")
        case .topLeft: return L10n.t("Oben links", "Top Left")
        case .topRight: return L10n.t("Oben rechts", "Top Right")
        case .bottomLeft: return L10n.t("Unten links", "Bottom Left")
        case .bottomRight: return L10n.t("Unten rechts", "Bottom Right")
        case .firstThird: return L10n.t("Erstes Drittel", "First Third")
        case .centerThird: return L10n.t("Mittleres Drittel", "Center Third")
        case .lastThird: return L10n.t("Letztes Drittel", "Last Third")
        case .firstTwoThirds: return L10n.t("Erste zwei Drittel", "First Two Thirds")
        case .lastTwoThirds: return L10n.t("Letzte zwei Drittel", "Last Two Thirds")
        case .maximize: return L10n.t("Maximieren", "Maximize")
        case .almostMaximize: return L10n.t("Nahezu maximieren", "Almost Maximize")
        case .maximizeHeight: return L10n.t("Höhe maximieren", "Maximize Height")
        case .smaller: return L10n.t("Verkleinern", "Make Smaller")
        case .larger: return L10n.t("Vergrößern", "Make Larger")
        case .center: return L10n.t("Zentrieren", "Center")
        case .restore: return L10n.t("Wiederherstellen", "Restore")
        case .nextDisplay: return L10n.t("Nächster Bildschirm", "Next Display")
        case .previousDisplay: return L10n.t("Vorheriger Bildschirm", "Previous Display")
        case .none: return L10n.t("Deaktiviert", "Disabled")
        }
    }
}

struct SnapKeyCombo: Codable, Equatable, Hashable {
    var modifiers: ModifierFlags
    var keyCode: UInt16

    var displayLabel: String {
        "\(modifiers.displaySymbols)\(KeyCodeTranslator.symbol(for: keyCode))"
    }
}

enum RepeatedSnapBehavior: String, Codable, CaseIterable, Identifiable {
    case doNothing
    case cycleThirds
    case moveToAdjacentDisplay

    var id: String { rawValue }

    @MainActor
    var localizedName: String {
        switch self {
        case .doNothing:
            return L10n.t("Nichts tun", "Do nothing")
        case .cycleThirds:
            return L10n.t("Drittel durchschalten (1/2 → 2/3 → 1/3)", "Cycle thirds (1/2 → 2/3 → 1/3)")
        case .moveToAdjacentDisplay:
            return L10n.t("Zum benachbarten Bildschirm bewegen", "Move to adjacent display")
        }
    }
}

enum SnapEdgeZone: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case top
    case topRight
    case left
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var id: String { rawValue }
}

struct WindowSnappingSettings: Codable, Equatable {
    var isEnabled: Bool = true
    var dragToSnapEnabled: Bool = true
    var restoreOnDrag: Bool = true
    var hapticFeedback: Bool = true
    var animateFootprint: Bool = true

    var windowGap: Double = 0
    var repeatedCommandBehavior: RepeatedSnapBehavior = .cycleThirds
    var moveCursorAcrossScreens: Bool = false
    var doubleClickTitleBarToMaximize: Bool = false
    var stageManagerMargin: Double = 0

    /// Keyed by SnapAction.rawValue
    var shortcuts: [String: SnapKeyCombo] = WindowSnappingSettings.defaultShortcuts()

    /// Keyed by SnapEdgeZone.rawValue -> SnapAction.rawValue
    var edgeZones: [String: SnapAction] = WindowSnappingSettings.defaultEdgeZones()

    func shortcut(for action: SnapAction) -> SnapKeyCombo? {
        shortcuts[action.rawValue]
    }

    mutating func setShortcut(_ combo: SnapKeyCombo?, for action: SnapAction) {
        if let combo {
            shortcuts[action.rawValue] = combo
        } else {
            shortcuts.removeValue(forKey: action.rawValue)
        }
    }

    func action(for zone: SnapEdgeZone) -> SnapAction {
        edgeZones[zone.rawValue] ?? .none
    }

    mutating func setAction(_ action: SnapAction, for zone: SnapEdgeZone) {
        edgeZones[zone.rawValue] = action
    }

    static func defaultShortcuts() -> [String: SnapKeyCombo] {
        let ctrlOpt: ModifierFlags = [.control, .option]
        let ctrlOptShift: ModifierFlags = [.control, .option, .shift]
        let ctrlOptCmd: ModifierFlags = [.control, .option, .command]

        return [
            SnapAction.leftHalf.rawValue:       SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_LeftArrow)),
            SnapAction.rightHalf.rawValue:      SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_RightArrow)),
            SnapAction.topHalf.rawValue:        SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_UpArrow)),
            SnapAction.bottomHalf.rawValue:     SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_DownArrow)),

            SnapAction.topLeft.rawValue:        SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_U)),
            SnapAction.topRight.rawValue:       SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_I)),
            SnapAction.bottomLeft.rawValue:     SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_J)),
            SnapAction.bottomRight.rawValue:    SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_K)),

            SnapAction.firstThird.rawValue:     SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_D)),
            SnapAction.centerThird.rawValue:    SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_F)),
            SnapAction.lastThird.rawValue:      SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_G)),
            SnapAction.firstTwoThirds.rawValue: SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_E)),
            SnapAction.lastTwoThirds.rawValue:  SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_T)),

            SnapAction.maximize.rawValue:       SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_Return)),
            SnapAction.maximizeHeight.rawValue: SnapKeyCombo(modifiers: ctrlOptShift, keyCode: UInt16(kVK_UpArrow)),
            SnapAction.smaller.rawValue:        SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_Minus)),
            SnapAction.larger.rawValue:         SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_Equal)),
            SnapAction.center.rawValue:         SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_ANSI_C)),
            SnapAction.restore.rawValue:        SnapKeyCombo(modifiers: ctrlOpt, keyCode: UInt16(kVK_Delete)),

            SnapAction.nextDisplay.rawValue:     SnapKeyCombo(modifiers: ctrlOptCmd, keyCode: UInt16(kVK_RightArrow)),
            SnapAction.previousDisplay.rawValue: SnapKeyCombo(modifiers: ctrlOptCmd, keyCode: UInt16(kVK_LeftArrow))
        ]
    }

    static func defaultEdgeZones() -> [String: SnapAction] {
        [
            SnapEdgeZone.topLeft.rawValue:     .topLeft,
            SnapEdgeZone.top.rawValue:         .maximize,
            SnapEdgeZone.topRight.rawValue:    .topRight,
            SnapEdgeZone.left.rawValue:        .leftHalf,
            SnapEdgeZone.right.rawValue:       .rightHalf,
            SnapEdgeZone.bottomLeft.rawValue:  .bottomLeft,
            SnapEdgeZone.bottom.rawValue:      .centerThird,
            SnapEdgeZone.bottomRight.rawValue: .bottomRight
        ]
    }
}
