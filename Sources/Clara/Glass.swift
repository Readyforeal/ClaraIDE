import SwiftUI
import AppKit

struct WallpaperGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }
    func updateNSView(_ view: ChromeView, context: Context) {}
    final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.isOpaque = false; window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            // Let AppKit provide the inset, toolbar-height traffic-light layout.
            if window.toolbar == nil {
                let toolbar = NSToolbar(identifier: "ClaraWindowControls")
                toolbar.displayMode = .iconOnly
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
        }
    }
}
extension View {
    func floatingGlass(enabled: Bool = true, tinted: Bool = false) -> some View {
        self.background {
            if enabled {
                Color.clear.glassEffect(.regular.tint(tinted ? .black.opacity(0.55) : .clear), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).strokeBorder(.white.opacity(enabled ? 0.10 : 0), lineWidth: 0.5).allowsHitTesting(false))
        .shadow(color: .black.opacity(enabled ? 0.28 : 0), radius: 22, y: 10)
    }
}

/// The button label defines the entire dock tile, including its empty padding.
struct DockButtonStyle: ButtonStyle {
    var radius: CGFloat = Palette.cornerRadius
    func makeBody(configuration: Configuration) -> some View {
        DockButtonBody(configuration: configuration, radius: radius)
    }
    private struct DockButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let radius: CGFloat
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.accent.opacity(enabled ? (configuration.isPressed ? 0.26 : hovered ? 0.14 : 0) : 0)))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.accent.opacity(enabled && hovered ? 0.32 : 0), lineWidth: 1).allowsHitTesting(false))
                .focusEffectDisabled()
                .pointerStyle(.default)
                .onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.12), value: hovered)
                .opacity(enabled ? 1 : 0.4)
        }
    }
}
struct DockIconButton: View {
    let icon: String
    let help: String
    var width: CGFloat = 38
    var height: CGFloat = 38
    var radius: CGFloat = Palette.cornerRadius
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13))
                .frame(width: width, height: height)
        }.buttonStyle(DockButtonStyle(radius: radius)).foregroundStyle(Palette.muted)
            .help(help).accessibilityLabel(help)
    }
}

/// Applied after clipping/glass so the close badge can overlap the tile's corner.
private struct DockCloseControl: ViewModifier {
    let enabled: Bool
    let radius: CGFloat
    let label: String
    let close: () -> Void
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Palette.accent.opacity(enabled && hovered ? 0.14 : 0))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(enabled && hovered ? 0.32 : 0), lineWidth: 1))
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                if enabled {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.icon)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(white: 0.16)))
                            .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 0.5).allowsHitTesting(false))
                    }
                    .buttonStyle(DockButtonStyle(radius: 10))
                    .help(label).accessibilityLabel(label)
                    .offset(x: 3, y: -3)
                    .opacity(hovered ? 1 : 0)
                    .allowsHitTesting(hovered)
                    .accessibilityHidden(!hovered)
                }
            }
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
extension View {
    func dockCloseControl(enabled: Bool, radius: CGFloat = Palette.cornerRadius, label: String, close: @escaping () -> Void) -> some View {
        modifier(DockCloseControl(enabled: enabled, radius: radius, label: label, close: close))
    }
}
