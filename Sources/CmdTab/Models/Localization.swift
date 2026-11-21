import Foundation

@MainActor
enum L10n {
    private static var bundleCache: [String: Bundle] = [:]

    static var resolvedCode: String {
        let lang = AppSettings.shared.payload.language
        if lang != .system {
            return lang.rawValue
        }
        guard let preferred = Locale.preferredLanguages.first else { return "en" }
        let lower = preferred.lowercased()
        if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw") || lower.hasPrefix("zh-hk") {
            return "zh-Hant"
        }
        if lower.hasPrefix("zh") {
            return "zh-Hans"
        }
        let base = String(lower.prefix(2))
        if AppLanguage.allCases.contains(where: { $0.rawValue == base }) {
            return base
        }
        return "en"
    }

    private static func bundle(for code: String) -> Bundle? {
        if let cached = bundleCache[code] {
            return cached
        }
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let b = Bundle(path: path) {
            bundleCache[code] = b
            return b
        }
        return nil
    }

    static func t(_ de: String, _ en: String) -> String {
        let code = resolvedCode
        if let b = bundle(for: code) {
            let localized = b.localizedString(forKey: en, value: "__MISSING__", table: nil)
            if localized != "__MISSING__" {
                return localized
            }
        }
        return code == "de" ? de : en
    }

    static func styleName(_ style: SwitcherStyle) -> String {
        switch style {
        case .thumbnails: return t("Miniaturen", "Thumbnails")
        case .appIcons: return t("App-Symbole", "App Icons")
        case .titles: return t("Titel", "Titles")
        }
    }

    static func sizeName(_ size: SwitcherSize) -> String {
        switch size {
        case .small: return t("Klein", "Small")
        case .medium: return t("Mittel", "Medium")
        case .large: return t("Groß", "Large")
        case .auto: return t("Automatisch", "Auto")
        }
    }

    static func appearanceName(_ mode: AppearanceMode) -> String {
        switch mode {
        case .light: return t("Hell", "Light")
        case .dark: return t("Dunkel", "Dark")
        case .system: return t("System", "System")
        }
    }

    static func releaseName(_ behavior: ReleaseBehavior) -> String {
        switch behavior {
        case .focus: return t("Fokus", "Focus")
        case .hold: return t("Halten", "Hold")
        case .search: return t("Suche", "Search")
        }
    }

    static func screenDisplayName(_ mode: ScreenDisplayMode) -> String {
        switch mode {
        case .activeScreen: return t("Aktiver Bildschirm", "Active Screen")
        case .mouseScreen: return t("Bildschirm mit Mauszeiger", "Screen with Mouse")
        case .mainScreen: return t("Hauptbildschirm", "Main Screen")
        }
    }

    static func appFilterName(_ mode: AppFilterMode) -> String {
        switch mode {
        case .allApps: return t("Alle Apps", "All Apps")
        case .activeApp: return t("Aktive App", "Active App")
        }
    }

    static func spaceFilterName(_ mode: SpaceFilterMode) -> String {
        switch mode {
        case .allSpaces: return t("Alle Spaces", "All Spaces")
        case .activeSpace: return t("Aktiver Space", "Active Space")
        }
    }

    static func screenFilterName(_ mode: ScreenFilterMode) -> String {
        switch mode {
        case .allScreens: return t("Alle Bildschirme", "All Screens")
        case .activeScreen: return t("Aktiver Bildschirm", "Active Screen")
        }
    }

    static func visibilityName(_ filter: VisibilityFilter) -> String {
        switch filter {
        case .show: return t("Anzeigen", "Show")
        case .hide: return t("Ausblenden", "Hide")
        case .showAtEnd: return t("Am Ende anzeigen", "Show at End")
        }
    }

    static func sortOrderName(_ order: SortOrder) -> String {
        switch order {
        case .recentlyUsed: return t("Zuletzt verwendet", "Recently Used")
        case .appName: return t("App-Name", "App Name")
        case .windowTitle: return t("Fenstertitel", "Window Title")
        case .spaceOrder: return t("Space-Reihenfolge", "Space Order")
        }
    }

    static func hideRuleName(_ rule: ExceptionHideRule) -> String {
        switch rule {
        case .never: return t("Nie", "Never")
        case .always: return t("Immer", "Always")
        case .whenNoOpenWindow: return t("Wenn kein Fenster geöffnet ist", "When no window is open")
        }
    }

    static func ignoreShortcutRuleName(_ rule: ExceptionIgnoreShortcutRule) -> String {
        switch rule {
        case .never: return t("Nie", "Never")
        case .always: return t("Immer", "Always")
        case .whenFullscreen: return t("Im Vollbildmodus", "When fullscreen")
        }
    }
}
