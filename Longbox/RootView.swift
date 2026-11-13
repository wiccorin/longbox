import SwiftUI

/// The two main screens and the bar that switches between them.
struct RootView: View {
    @State private var tab = 0

    var body: some View {
        ZStack {
            // Both stay alive so each keeps its scroll position.
            LibraryView()
                .opacity(tab == 0 ? 1 : 0)
                .allowsHitTesting(tab == 0)
                .accessibilityHidden(tab != 0)
            FoldersView()
                .opacity(tab == 1 ? 1 : 0)
                .allowsHitTesting(tab == 1)
                .accessibilityHidden(tab != 1)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bar: some View {
        HStack(spacing: 0) {
            tabButton(0, title: "BOX", symbol: "shippingbox.fill")
            tabButton(1, title: "FOLDERS", symbol: "folder.fill")
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
                    .font(.system(size: 19, weight: .bold))
                Text(title)
                    .font(Theme.display(15))
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
