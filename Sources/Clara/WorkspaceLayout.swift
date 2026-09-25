import Foundation

/// Shared by chat and floating panels so their bounds never overlap.
struct WorkspaceLayout {
    static let panelInset: CGFloat = 14
    static let panelGap: CGFloat = 12
    static let bottomClearance: CGFloat = 62
    static let dockItemSize: CGFloat = 42
    static let dockPadding: CGFloat = 6
    static let dockWidth = dockItemSize + 2 * dockPadding
    let chatWidth: CGFloat
    let navigatorWidth: CGFloat
    let navigatorX: CGFloat
    let editorX: CGFloat
    let editorWidth: CGFloat
    let dockX: CGFloat
    init(width: CGFloat, navigatorOpen: Bool, editorOpen: Bool, hasDockedFiles: Bool) {
        let inset = Self.panelInset
        navigatorWidth = navigatorOpen ? min(224, max(180, width * 0.18)) : Self.dockWidth
        dockX = width - inset - (Self.dockItemSize + (navigatorOpen ? 0 : Self.dockPadding))
        let dockContainerX = width - inset - Self.dockWidth
        let rightEdge = navigatorOpen ? (hasDockedFiles ? dockX - 12 : width - inset) : dockContainerX - 12
        if editorOpen {
            chatWidth = min(340, max(240, width * 0.26))
            navigatorX = navigatorOpen ? chatWidth + Self.panelGap : dockContainerX
        } else {
            navigatorX = navigatorOpen ? rightEdge - navigatorWidth : dockContainerX
            chatWidth = max(240, navigatorX - inset)
        }
        editorX = navigatorOpen ? navigatorX + navigatorWidth + Self.panelGap : chatWidth + Self.panelGap
        editorWidth = max(240, rightEdge - editorX)
    }
}

/// A terminal's snap position is retained while its session is docked.
enum TerminalPlacement: String, CaseIterable {
    case full, bottom, right

    static func destination(for translation: CGSize, current: Self) -> Self {
        guard max(abs(translation.width), abs(translation.height)) >= 48 else { return current }
        if abs(translation.width) > abs(translation.height) {
            return translation.width > 0 ? .right : .full
        }
        return translation.height > 0 ? .bottom : .full
    }
}

struct TerminalLayout {
    let terminal: CGRect
    let chat: CGRect
    let chatBottomPadding: CGFloat

    init(size: CGSize, placement: TerminalPlacement) {
        let inset = WorkspaceLayout.panelInset
        let gap = WorkspaceLayout.panelGap
        let width = max(0, size.width - 2 * inset)
        let height = max(0, size.height - inset - WorkspaceLayout.bottomClearance)
        switch placement {
        case .full:
            terminal = CGRect(x: inset, y: inset, width: width, height: height)
            chat = CGRect(origin: .zero, size: size)
            chatBottomPadding = WorkspaceLayout.bottomClearance
        case .bottom:
            let half = max(0, (height - gap) / 2)
            terminal = CGRect(x: inset, y: inset + half + gap, width: width, height: half)
            chat = CGRect(x: 0, y: 0, width: size.width, height: inset + half)
            chatBottomPadding = 0
        case .right:
            let half = max(0, (width - gap) / 2)
            terminal = CGRect(x: inset + half + gap, y: inset, width: half, height: height)
            chat = CGRect(x: 0, y: 0, width: inset + half, height: size.height)
            chatBottomPadding = WorkspaceLayout.bottomClearance
        }
    }
}
