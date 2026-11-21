import AppKit
import SwiftUI

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var appearance: NSAppearance?

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = appearance
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.appearance = appearance
    }
}

@MainActor
final class SwitcherViewModel: ObservableObject {
    @Published var allWindows: [WindowInfo] = []
    @Published var filteredWindows: [WindowInfo] = []
    @Published var matchedIndicesByID: [String: Set<Int>] = [:]
    @Published var selectedIndex: Int = 0
    @Published var searchQuery: String = "" {
        didSet { applySearchFilter() }
    }
    @Published var isSearchActive: Bool = false
    @Published var activeShortcut: ShortcutConfig?
    @Published var hoveredWindowID: String?

    var onSelectAndFocus: ((WindowInfo) -> Void)?
    var onCloseWindow: ((WindowInfo) -> Void)?
    var onMinimizeWindow: ((WindowInfo) -> Void)?
    var onFullscreenWindow: ((WindowInfo) -> Void)?
    var onTogglePin: ((WindowInfo) -> Void)?
    var onSnapWindow: ((WindowInfo, WindowSnapPosition) -> Void)?
    var onSelectionChanged: ((WindowInfo?) -> Void)?

    var effectiveStyle: SwitcherStyle {
        activeShortcut?.styleOverride ?? AppSettings.shared.payload.style
    }

    var selectedWindow: WindowInfo? {
        guard filteredWindows.indices.contains(selectedIndex) else { return nil }
        return filteredWindows[selectedIndex]
    }

    func load(windows: [WindowInfo], shortcut: ShortcutConfig, initialSelection: Int, openSearch: Bool) {
        self.activeShortcut = shortcut
        self.allWindows = windows
        self.searchQuery = ""
        self.isSearchActive = openSearch
        self.matchedIndicesByID = [:]
        self.filteredWindows = windows
        self.selectedIndex = windows.isEmpty ? 0 : min(max(0, initialSelection), windows.count - 1)
        onSelectionChanged?(selectedWindow)
    }

    func updateThumbnail(windowID: CGWindowID, image: NSImage) {
        for i in allWindows.indices where allWindows[i].windowID == windowID {
            allWindows[i].thumbnail = image
        }
        for i in filteredWindows.indices where filteredWindows[i].windowID == windowID {
            filteredWindows[i].thumbnail = image
        }
    }

    func applySearchFilter() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty {
            filteredWindows = allWindows
            matchedIndicesByID = [:]
        } else {
            var scored: [(WindowInfo, Int, Set<Int>)] = []
            for win in allWindows {
                let titleMatch = FuzzyMatcher.match(query: q, in: win.displayTitle)
                let appMatch = FuzzyMatcher.match(query: q, in: win.appName)
                if let tm = titleMatch {
                    scored.append((win, tm.score + (appMatch?.score ?? 0) / 3, tm.matchedIndices))
                } else if let am = appMatch {
                    scored.append((win, am.score, []))
                }
            }
            scored.sort { $0.1 > $1.1 }
            filteredWindows = scored.map(\.0)
            matchedIndicesByID = Dictionary(uniqueKeysWithValues: scored.map { ($0.0.id, $0.2) })
        }

        if filteredWindows.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= filteredWindows.count {
            selectedIndex = 0
        }
        onSelectionChanged?(selectedWindow)
    }

    func stepSelection(delta: Int) {
        guard !filteredWindows.isEmpty else { return }
        let count = filteredWindows.count
        selectedIndex = (selectedIndex + delta % count + count) % count
        onSelectionChanged?(selectedWindow)
    }

    func moveSelection(direction: NavigationDirection, columns: Int) {
        guard !filteredWindows.isEmpty else { return }
        let count = filteredWindows.count
        let cols = max(1, columns)

        switch direction {
        case .left:
            selectedIndex = (selectedIndex - 1 + count) % count
        case .right:
            selectedIndex = (selectedIndex + 1) % count
        case .up:
            let next = selectedIndex - cols
            selectedIndex = next >= 0 ? next : max(0, count - 1)
        case .down:
            let next = selectedIndex + cols
            selectedIndex = next < count ? next : selectedIndex % cols
        }
        onSelectionChanged?(selectedWindow)
    }

    func select(index: Int) {
        guard filteredWindows.indices.contains(index) else { return }
        selectedIndex = index
        onSelectionChanged?(selectedWindow)
    }
}

struct SwitcherView: View {
    @ObservedObject var viewModel: SwitcherViewModel
    @ObservedObject var settings = AppSettings.shared

    let maxWidth: CGFloat
    let maxHeight: CGFloat

    private var colorScheme: ColorScheme? {
        switch settings.payload.appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    private var nsAppearance: NSAppearance? {
        switch settings.payload.appearance {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    var body: some View {
        let style = viewModel.effectiveStyle

        VStack(spacing: 12) {
            if viewModel.isSearchActive || !viewModel.searchQuery.isEmpty {
                searchBar
            }

            if viewModel.filteredWindows.isEmpty {
                emptyState
            } else {
                switch style {
                case .thumbnails:
                    thumbnailsGrid
                case .appIcons:
                    appIconsBar
                case .titles:
                    titlesList
                }
            }

            footerHintBar
        }
        .padding(16)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .behindWindow, appearance: nsAppearance)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .shadow(color: .black.opacity(0.32), radius: 30, y: 12)
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        .preferredColorScheme(colorScheme)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)

            Text(viewModel.searchQuery.isEmpty ? L10n.t("Fenster oder App suchen…", "Search windows or apps…") : viewModel.searchQuery)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(viewModel.searchQuery.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(viewModel.filteredWindows.count) \(L10n.t("von", "of")) \(viewModel.allWindows.count) \(L10n.t("Fenstern", "windows"))")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                )
        )
    }

    // MARK: - Thumbnails Style (Auto-Sizing Grid)

    private var thumbnailsGrid: some View {
        let metrics = computeThumbnailMetrics(count: viewModel.filteredWindows.count)
        let columns = Array(repeating: GridItem(.fixed(metrics.cardWidth), spacing: 12), count: metrics.columns)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(viewModel.filteredWindows.enumerated()), id: \.element.id) { index, window in
                        ThumbnailCardView(
                            window: window,
                            index: index,
                            isSelected: index == viewModel.selectedIndex,
                            isHovered: viewModel.hoveredWindowID == window.id,
                            matchedIndices: viewModel.matchedIndicesByID[window.id] ?? [],
                            cardWidth: metrics.cardWidth,
                            thumbHeight: metrics.thumbHeight,
                            showBadges: settings.payload.showStatusBadges,
                            showQuickJump: settings.payload.showQuickJumpNumbers && !viewModel.isSearchActive,
                            showHoverActions: settings.payload.showHoverWindowActions,
                            showSnapActions: settings.payload.showWindowSnappingActions,
                            onSelect: { viewModel.onSelectAndFocus?(window) },
                            onClose: { viewModel.onCloseWindow?(window) },
                            onMinimize: { viewModel.onMinimizeWindow?(window) },
                            onFullscreen: { viewModel.onFullscreenWindow?(window) },
                            onTogglePin: { viewModel.onTogglePin?(window) },
                            onSnap: { pos in viewModel.onSnapWindow?(window, pos) }
                        )
                        .id(window.id)
                        .onHover { hovering in
                            if hovering {
                                viewModel.hoveredWindowID = window.id
                            } else if viewModel.hoveredWindowID == window.id {
                                viewModel.hoveredWindowID = nil
                            }
                        }
                    }
                }
                .padding(2)
            }
            .frame(
                width: CGFloat(metrics.columns) * metrics.cardWidth + CGFloat(max(0, metrics.columns - 1)) * 12 + 4,
                height: min(maxHeight - 110, CGFloat(metrics.rows) * (metrics.thumbHeight + 44) + CGFloat(max(0, metrics.rows - 1)) * 12 + 4)
            )
            .onChange(of: viewModel.selectedIndex) { _, newIdx in
                if viewModel.filteredWindows.indices.contains(newIdx) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(viewModel.filteredWindows[newIdx].id, anchor: .center)
                    }
                }
            }
        }
    }

    private struct GridMetrics {
        let columns: Int
        let rows: Int
        let cardWidth: CGFloat
        let thumbHeight: CGFloat
    }

    private func computeThumbnailMetrics(count: Int) -> GridMetrics {
        let safeCount = max(1, count)
        let usableWidth = max(400, maxWidth - 44)

        let baseCardWidth: CGFloat
        switch settings.payload.size {
        case .small:
            baseCardWidth = 185
        case .medium:
            baseCardWidth = 245
        case .large:
            baseCardWidth = 310
        case .auto:
            // Auto-sizing just like AltTab Pro: big previews for 1-4 windows, compact grid for 10-12+ windows!
            if safeCount <= 3 {
                baseCardWidth = 310
            } else if safeCount <= 5 {
                baseCardWidth = 250
            } else if safeCount <= 8 {
                baseCardWidth = 215
            } else {
                baseCardWidth = 185
            }
        }

        let maxColsThatFit = max(1, Int((usableWidth + 12) / (baseCardWidth + 12)))
        let cols = min(safeCount, maxColsThatFit)
        let rows = Int(ceil(Double(safeCount) / Double(cols)))
        let thumbHeight = round(baseCardWidth * 0.62)

        return GridMetrics(columns: cols, rows: rows, cardWidth: baseCardWidth, thumbHeight: thumbHeight)
    }

    // MARK: - App Icons Style

    private var appIconsBar: some View {
        let iconSize: CGFloat = {
            switch settings.payload.size {
            case .small: return 56
            case .medium: return 72
            case .large: return 88
            case .auto: return viewModel.filteredWindows.count > 10 ? 58 : 74
            }
        }()

        return VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.filteredWindows.enumerated()), id: \.element.id) { index, window in
                        let isSelected = index == viewModel.selectedIndex
                        VStack(spacing: 6) {
                            ZStack(alignment: .topTrailing) {
                                Image(nsImage: window.appIcon)
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: iconSize, height: iconSize)
                                    .opacity(window.isMinimized || window.isHidden ? 0.55 : 1.0)

                                if window.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(Color.orange))
                                        .offset(x: 4, y: -4)
                                } else if settings.payload.showQuickJumpNumbers && !viewModel.isSearchActive && index < 9 {
                                    Text("\(index + 1)")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(Color.black.opacity(0.65)))
                                        .offset(x: 4, y: -4)
                                }
                            }
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                                    )
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.onSelectAndFocus?(window)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            if let selected = viewModel.selectedWindow {
                HStack(spacing: 8) {
                    HighlightedTextView(
                        text: selected.displayTitle,
                        matchedIndices: viewModel.matchedIndicesByID[selected.id] ?? [],
                        font: .system(size: 14, weight: .semibold)
                    )
                    .lineLimit(1)

                    StatusBadgesRow(window: selected, compact: true)
                }
            }
        }
    }

    // MARK: - Titles Style (Compact List)

    private var titlesList: some View {
        let rowWidth = min(maxWidth - 44, 540)

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(viewModel.filteredWindows.enumerated()), id: \.element.id) { index, window in
                        let isSelected = index == viewModel.selectedIndex
                        HStack(spacing: 10) {
                            if settings.payload.showQuickJumpNumbers && !viewModel.isSearchActive && index < 9 {
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                                    .frame(width: 18)
                            }

                            Image(nsImage: window.appIcon)
                                .resizable()
                                .frame(width: 22, height: 22)

                            HighlightedTextView(
                                text: window.displayTitle,
                                matchedIndices: viewModel.matchedIndicesByID[window.id] ?? [],
                                font: .system(size: 14, weight: isSelected ? .semibold : .regular)
                            )
                            .lineLimit(1)

                            if window.displayTitle != window.appName {
                                Text("— \(window.appName)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            if window.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.orange)
                            }

                            if settings.payload.showStatusBadges {
                                StatusBadgesRow(window: window, compact: true)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(width: rowWidth, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                )
                        )
                        .contentShape(Rectangle())
                        .id(window.id)
                        .onTapGesture {
                            viewModel.onSelectAndFocus?(window)
                        }
                    }
                }
            }
            .frame(width: rowWidth, height: min(maxHeight - 110, CGFloat(viewModel.filteredWindows.count) * 42 + 8))
            .onChange(of: viewModel.selectedIndex) { _, newIdx in
                if viewModel.filteredWindows.indices.contains(newIdx) {
                    proxy.scrollTo(viewModel.filteredWindows[newIdx].id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Empty & Footer

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(L10n.t("Keine passenden Fenster gefunden", "No matching windows found"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 340, height: 110)
    }

    private var footerHintBar: some View {
        HStack(spacing: 14) {
            hintChip("↩", L10n.t("Fokus", "Focus"))
            hintChip("Space", L10n.t("Suche", "Search"))
            hintChip("W", L10n.t("Schließen", "Close"))
            hintChip("M", L10n.t("Minimieren", "Minimize"))
            hintChip("P", L10n.t("Pinnen", "Pin"))
            if settings.payload.showWindowSnappingActions {
                hintChip("[ ] \\", L10n.t("Andocken", "Snap"))
            }
            Spacer(minLength: 0)
            if let shortcutName = viewModel.activeShortcut?.name {
                Text(shortcutName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }

    private func hintChip(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Thumbnail Card

private struct ThumbnailCardView: View {
    let window: WindowInfo
    let index: Int
    let isSelected: Bool
    let isHovered: Bool
    let matchedIndices: Set<Int>
    let cardWidth: CGFloat
    let thumbHeight: CGFloat
    let showBadges: Bool
    let showQuickJump: Bool
    let showHoverActions: Bool
    let showSnapActions: Bool

    let onSelect: () -> Void
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onFullscreen: () -> Void
    let onTogglePin: () -> Void
    let onSnap: (WindowSnapPosition) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: App Icon + Title + QuickJump / Pin
            HStack(spacing: 7) {
                Image(nsImage: window.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 20, height: 20)

                HighlightedTextView(
                    text: window.displayTitle,
                    matchedIndices: matchedIndices,
                    font: .system(size: 13, weight: .semibold)
                )
                .lineLimit(1)

                Spacer(minLength: 2)

                if window.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }

                if showQuickJump && index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.1))
                        )
                }
            }

            // Preview area
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                if let thumb = window.thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .opacity(window.isMinimized || window.isHidden ? 0.6 : 1.0)
                        .padding(2)
                } else {
                    VStack(spacing: 6) {
                        Image(nsImage: window.appIcon)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .opacity(0.85)
                        if window.isWindowlessApp {
                            Text(L10n.t("Kein offenes Fenster", "No open window"))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Bottom overlays: status badges & hover window actions
                VStack {
                    Spacer()
                    if isHovered && showHoverActions && !window.isWindowlessApp {
                        hoverActionBar
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    } else if showBadges {
                        HStack {
                            Spacer()
                            StatusBadgesRow(window: window, compact: false)
                        }
                        .padding(6)
                    }
                }
            }
            .frame(height: thumbHeight)
            .clipped()
        }
        .padding(10)
        .frame(width: cardWidth)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 2.5 : 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }

    private var hoverActionBar: some View {
        HStack(spacing: 7) {
            circleAction(color: Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark", help: L10n.t("Schließen", "Close"), action: onClose)
            circleAction(color: Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus", help: L10n.t("Minimieren", "Minimize"), action: onMinimize)
            circleAction(color: Color(red: 0.16, green: 0.78, blue: 0.25), symbol: "arrow.up.left.and.arrow.down.right", help: L10n.t("Vollbild", "Fullscreen"), action: onFullscreen)

            Divider()
                .frame(height: 14)

            iconAction(symbol: window.isPinned ? "pin.slash.fill" : "pin.fill", tint: .orange, help: L10n.t("Pinnen", "Pin"), action: onTogglePin)

            if showSnapActions {
                iconAction(symbol: "rectangle.lefthalf.filled", tint: .primary, help: L10n.t("Links andocken", "Snap Left")) {
                    onSnap(.leftHalf)
                }
                iconAction(symbol: "rectangle.righthalf.filled", tint: .primary, help: L10n.t("Rechts andocken", "Snap Right")) {
                    onSnap(.rightHalf)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        )
        .padding(.bottom, 8)
    }

    private func circleAction(color: Color, symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.black.opacity(0.78))
                .frame(width: 20, height: 20)
                .background(Circle().fill(color))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func iconAction(symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Status Badges & Highlighted Search Text

private struct StatusBadgesRow: View {
    let window: WindowInfo
    let compact: Bool

    var body: some View {
        HStack(spacing: 4) {
            if window.isMinimized {
                badge(icon: "minus", text: L10n.t("Minimiert", "Minimized"))
            }
            if window.isHidden {
                badge(icon: "eye.slash", text: L10n.t("Ausgeblendet", "Hidden"))
            }
            if window.isFullscreen {
                badge(icon: "arrow.up.left.and.arrow.down.right", text: L10n.t("Vollbild", "Fullscreen"))
            }
            if let space = window.spaceIndex, !window.isOnActiveSpace {
                badge(icon: "square.grid.2x2", text: "Space \(space)")
            }
        }
    }

    private func badge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
            Text(text)
                .font(.system(size: compact ? 10 : 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.72))
        )
    }
}

private struct HighlightedTextView: View {
    let text: String
    let matchedIndices: Set<Int>
    let font: Font

    var body: some View {
        if matchedIndices.isEmpty {
            Text(text).font(font)
        } else {
            Text(buildAttributedString())
                .font(font)
        }
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        for (idx, ch) in text.enumerated() {
            var part = AttributedString(String(ch))
            if matchedIndices.contains(idx) {
                part.backgroundColor = Color.yellow.opacity(0.38)
                part.foregroundColor = Color.primary
            }
            result.append(part)
        }
        return result
    }
}
