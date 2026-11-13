import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let bookID: UUID

    @State private var page = 0
    @State private var ready = false
    @State private var showChrome = true

    private var book: Book? { store.book(bookID) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let book, ready {
                let urls = Storage.pageURLs(for: book)
                Group {
                    if book.mode == .vertical {
                        VerticalReader(urls: urls, page: $page, onTap: toggleChrome)
                    } else {
                        PagedReader(
                            urls: urls,
                            rightToLeft: book.mode == .rightToLeft,
                            page: $page,
                            onCenterTap: toggleChrome
                        )
                    }
                }
                .ignoresSafeArea()

                if showChrome {
                    chrome(book)
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(showChrome ? .automatic : .hidden)
        .onAppear {
            if !ready {
                page = book?.currentPage ?? 0
                ready = true
            }
        }
        .onChange(of: page) { newValue in
            store.setPage(newValue, for: bookID)
        }
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showChrome.toggle()
        }
    }

    private func chrome(_ book: Book) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    store.setPage(page, for: bookID)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Close")

                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Picker("Reading direction", selection: Binding(
                        get: { book.mode },
                        set: { store.setMode($0, for: bookID) }
                    )) {
                        ForEach(ReadingMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel("Reading direction")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)

            Spacer()

            VStack(spacing: 6) {
                if book.pageCount > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(page) },
                            set: { page = Int($0.rounded()) }
                        ),
                        in: 0...Double(book.pageCount - 1),
                        step: 1
                    )
                    .environment(\.layoutDirection, book.mode == .rightToLeft ? .rightToLeft : .leftToRight)
                    .accessibilityLabel("Page")
                }
                Text("\(page + 1) / \(book.pageCount)")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
        }
        .foregroundStyle(.white)
    }
}

/// Continuous top-to-bottom reading, for webtoons and long strips.
struct VerticalReader: View {
    let urls: [URL]
    @Binding var page: Int
    let onTap: () -> Void

    /// The last page this view reported itself, so outside jumps (the slider) can be told apart.
    @State private var reported = -1

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(urls.indices, id: \.self) { index in
                        StripPage(url: urls[index])
                            .id(index)
                            .onAppear {
                                reported = index
                                if page != index { page = index }
                            }
                    }
                }
            }
            .onAppear {
                reported = page
                proxy.scrollTo(page, anchor: .top)
            }
            .onChange(of: page) { newValue in
                if newValue != reported {
                    reported = newValue
                    proxy.scrollTo(newValue, anchor: .top)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct StripPage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var aspect: CGFloat = 0.7

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.black
                    .aspectRatio(aspect, contentMode: .fit)
                    .overlay { ProgressView().tint(.white) }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: url) {
            if let size = PageImage.pixelSize(url) {
                aspect = size.width / size.height
            }
            image = await PageImage.page(url)
        }
    }
}
