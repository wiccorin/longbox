import SwiftUI

/// The main screens and the bar that switches between them.
struct RootView: View {
    /// 0 Box, 1 Folders, 2 Picks, 3 Clippings, 4 Stats. The app opens on the Box.
    @State private var tab = 0

    var body: some View {
        ZStack {
            // All stay alive so each keeps its scroll position.
            screen(0) { LibraryView() }
            screen(1) { FoldersView() }
            screen(2) { PicksView() }
            screen(3) { ClippingsView() }
            screen(4) { StatsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func screen<Content: View>(_ index: Int, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .opacity(tab == index ? 1 : 0)
            .allowsHitTesting(tab == index)
            .accessibilityHidden(tab != index)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            tabButton(1, title: "FOLDERS", symbol: "folder.fill")
            tabButton(3, title: "CLIPS", symbol: "scissors")
            tabButton(0, title: "BOX", symbol: "shippingbox.fill")
            tabButton(2, title: "PICKS", symbol: "sparkles")
            tabButton(4, title: "STATS", symbol: "chart.bar.fill")
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Theme.ink.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.yellow)
                .frame(height: 3)
        }
    }

    private func tabButton(_ index: Int, title: String, symbol: String) -> some View {
        let selected = tab == index
        return Button {
            tab = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(height: 22)
                Text(title)
                    .font(Theme.display(13))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(selected ? Theme.yellow : Theme.paper.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressDownStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
