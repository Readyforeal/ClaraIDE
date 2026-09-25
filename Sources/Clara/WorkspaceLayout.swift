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
