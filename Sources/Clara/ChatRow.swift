import SwiftUI
import AppKit

struct ChatRow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chat: Conversation
    @State private var hovered = false
    @State private var offset: CGFloat = 0
    private var selected: Bool { chat.id == store.chat?.id && !store.showingIssues }
    var body: some View {
        HStack(spacing: 0) {
            Button { store.selectChat(chat.id) } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1).fill(selected ? Palette.accent : .clear).frame(width: 2, height: 14)
                    GeometryReader { geometry in
                        let textWidth = (chat.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
                        let overflow = max(0, textWidth - geometry.size.width + 4)
                        Text(chat.title).font(.system(size: 11)).fixedSize().offset(x: -offset)
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
                            .clipped()
                            .mask(LinearGradient(stops: [.init(color: .clear, location: offset > 0 ? 0 : 0), .init(color: .black, location: offset > 0 ? 0.06 : 0), .init(color: .black, location: 0.80), .init(color: overflow > 0 ? .clear : .black, location: 1)], startPoint: .leading, endPoint: .trailing))
                            .task(id: "\(hovered)-\(geometry.size.width)-\(chat.title)-\(reduceMotion)") {
                                offset = 0
                                guard hovered, overflow > 0, !reduceMotion else { return }
                                do {
                                    while !Task.isCancelled {
                                        try await Task.sleep(for: .seconds(1))
                                        let duration = Double(overflow / 22)
                                        withAnimation(.linear(duration: duration)) { offset = overflow }
                                        try await Task.sleep(for: .seconds(duration + 1.5))
                                        withAnimation(.easeOut(duration: 0.25)) { offset = 0 }
                                        try await Task.sleep(for: .seconds(0.4))
                                    }
                                } catch { offset = 0 }
                            }
                    }.frame(height: 18)
                }.padding(.leading, 26).frame(maxWidth: .infinity).frame(height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(selected ? .white : Palette.muted).help(chat.title)
            Button { store.deleteChat(chat.id) } label: {
                Image(systemName: "trash").font(.system(size: 11)).frame(width: 28, height: 30)
            }.buttonStyle(DockButtonStyle()).foregroundStyle(Palette.icon)
                .opacity(hovered ? 1 : 0).allowsHitTesting(hovered)
                .accessibilityLabel("Delete conversation: " + chat.title)
                .help("Delete conversation (Undo available)")
                .overlay { if !hovered && store.runningChat == chat.id { Circle().fill(Palette.accent).frame(width: 5, height: 5).allowsHitTesting(false) } }
        }.padding(.trailing, 4)
            .background(selected ? Palette.accent.opacity(0.12) : hovered ? Color.white.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: Palette.cornerRadius))
            .onHover { hovered = $0 }.pointerStyle(.default)
            .contextMenu { Button("Delete conversation") { store.deleteChat(chat.id) } }
    }
}
