import SwiftUI

struct SidebarAction: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var selected = false
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(Palette.icon).frame(width: 18)
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                if let shortcut { Text(shortcut).font(.system(size: 10)).foregroundStyle(Palette.muted) }
            }.padding(.horizontal, 8).frame(height: 38)
                .contentShape(RoundedRectangle(cornerRadius: Palette.cornerRadius))
                .background(selected || hovered ? Color.white.opacity(selected ? 0.07 : 0.04) : .clear,
                            in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
        }.buttonStyle(.plain).focusEffectDisabled().pointerStyle(.default)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Inbox shell for the future custom issue tunnel. No fabricated issues or
/// repository actions are exposed before the integration is implemented.
struct IssuesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues").font(.system(size: 30, weight: .medium)).tracking(-0.8)
                    Text("From reported problem to proposed fix.").font(.system(size: 13)).foregroundStyle(Palette.muted)
                }
                VStack(spacing: 18) {
                    Image(systemName: "tray").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.icon)
                    Text("Your next fix starts here.").font(.system(size: 20, weight: .medium))
                    Text("Issues from your custom tracking tunnel will arrive in this inbox, ready to review and hand off to Clara.")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).lineSpacing(5)
                        .multilineTextAlignment(.center).frame(maxWidth: 400)
                    HStack(spacing: 7) {
                        Image(systemName: "link").foregroundStyle(Palette.icon)
                        Text("Waiting for tunnel integration")
                    }.font(.system(size: 10)).foregroundStyle(Palette.muted).padding(.top, 6)
                }.frame(maxWidth: .infinity).padding(.vertical, 66).padding(.horizontal, 24)
                    .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous).strokeBorder(Palette.line))
                VStack(alignment: .leading, spacing: 18) {
                    Text("THE PLANNED WORKFLOW").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted)
                    HStack(alignment: .top, spacing: 24) {
                        step("folder", "Open repository", "Find or open the issue’s project.")
                        step("arrow.triangle.branch", "Create a branch", "Keep the fix in its own branch.")
                        step("wrench.and.screwdriver", "Make the fix", "Use your selected AI model.")
                        step("arrow.triangle.pull", "Build the PR", "Prepare the change for review.")
                    }
                    Text("Once connected, choose an issue and select Propose fix to begin. The tunnel and automated branch-to-PR workflow are not connected yet.")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4).padding(.top, 4)
                }
            }.frame(maxWidth: 840).padding(.horizontal, 40).padding(.vertical, 42).frame(maxWidth: .infinity)
        }
    }
    private func step(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Palette.icon)
            Text(title).font(.system(size: 11, weight: .medium))
            Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted).lineSpacing(3)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
