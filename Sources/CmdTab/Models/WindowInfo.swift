import AppKit
import ApplicationServices
import Foundation

struct WindowInfo: Identifiable, Equatable {
    let id: String
    let windowID: CGWindowID
    let pid: pid_t
    let bundleIdentifier: String
    let appName: String
    var title: String
    let appIcon: NSImage
    var thumbnail: NSImage?
    var frame: CGRect
    var isMinimized: Bool
    var isHidden: Bool
    var isFullscreen: Bool
    var isWindowlessApp: Bool
    var spaceIndex: Int?
    var isOnActiveSpace: Bool
    var screenID: CGDirectDisplayID?
    var axWindow: AXUIElement?
    var lastFocusedAt: Date
    var isPinned: Bool

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appName : trimmed
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.isMinimized == rhs.isMinimized &&
        lhs.isHidden == rhs.isHidden &&
        lhs.isFullscreen == rhs.isFullscreen &&
        lhs.spaceIndex == rhs.spaceIndex &&
        lhs.isPinned == rhs.isPinned &&
        (lhs.thumbnail === rhs.thumbnail)
    }
}

enum WindowSnapPosition: String, CaseIterable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case center
}
