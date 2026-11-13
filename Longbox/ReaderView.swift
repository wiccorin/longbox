import SwiftUI

struct ReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let bookID: UUID

    @State private var page = 0
    @State private var ready = false
    @State private var showChrome = true
    @State private var aspects: [CGFloat]?
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var urls: [URL] = []
    @State private var saveTask: Task<Void, Never>?

    private var book: Book? { store.book(bookID) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let book, ready {
                Group {
                    if book.mode == .vertical {
                        if let aspects, aspects.count == urls.count {
                            StripReader(urls: urls, aspects: aspects, page: $page, onTap: toggleChrome)
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
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
                .task(id: book.mode) {
                    if book.mode == .vertical && aspects == nil {
                        aspects = await PageImage.aspects(urls)
                    }
                }

                if showChrome {
                    chrome(book, urls: urls)
                        .transition(.opacity)
                }
            }
        }
        .statusBarHidden(!showChrome)
        .persistentSystemOverlays(showChrome ? .automatic : .hidden)
        .onAppear {
            if !ready {
                page = book?.currentPage ?? 0
                scrub = Double(page)
                if let book {
                    urls = Storage.pageURLs(for: book)
                }
                ready = true
            }
        }
        .onChange(of: page) { newValue in
            if !scrubbing {
                scrub = Double(newValue)
            }
            // Saving on every page turn stutters the scroll, so wait for a pause.
            saveTask?.cancel()
            saveTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 800_000_000)
                if !Task.isCancelled {
                    store.setPage(newValue, for: bookID)
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active && ready {
                saveTask?.cancel()
                store.setPage(page, for: bookID)
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if ready {
                store.setPage(page, for: bookID)
            }
        }
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showChrome.toggle()
        }
    }

    // MARK: Chrome

    private func chrome(_ book: Book, urls: [URL]) -> some View {
        VStack(spacing: 0) {
            topBar(book)
            Spacer(minLength: 0)
            if scrubbing, urls.indices.contains(Int(scrub.rounded())) {
                ScrubPreview(url: urls[Int(scrub.rounded())], number: Int(scrub.rounded()) + 1)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
            bottomBar(book)
        }
    }

    private func topBar(_ book: Book) -> some View {
        HStack(spacing: 8) {
            Button {
                store.setPage(page, for: bookID)
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .black))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")

            Text(book.title)
                .font(Theme.display(21))
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
                Divider()
                Button {
                    store.addChapter(at: page, for: bookID)
                } label: {
                    Label("Mark chapter start here", systemImage: "bookmark")
                }
                if !book.chapterList.isEmpty {
                    Menu("Jump to chapter") {
                        ForEach(Array(book.chapterList.enumerated()), id: \.offset) { index, chapter in
                            Button(chapter.displayTitle(index)) {
                                page = chapter.startPage
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: book.mode.symbol)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.yellow))
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Reading direction")
        }
        .foregroundColor(Theme.paper)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Theme.ink.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.yellow)
                .frame(height: 3)
        }
    }

    private func bottomBar(_ book: Book) -> some View {
        let shown = scrubbing ? Int(scrub.rounded()) : page
        return VStack(spacing: 10) {
            if book.pageCount > 1 {
                Slider(
                    value: $scrub,
                    in: 0...Double(book.pageCount - 1),
                    step: 1,
                    onEditingChanged: { editing in
                        withAnimation(.easeOut(duration: 0.12)) {
                            scrubbing = editing
                        }
                        if !editing {
                            page = Int(scrub.rounded())
                        }
                    }
                )
                .tint(Theme.yellow)
                .environment(\.layoutDirection, book.mode == .rightToLeft ? .rightToLeft : .leftToRight)
                .accessibilityLabel("Page")
            }
            CaptionBox(text: "Page \(shown + 1) of \(book.pageCount)", shadow: .black)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.ink.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.yellow)
                .frame(height: 3)
        }
    }
}

/// The floating page preview shown while dragging the scrubber.
private struct ScrubPreview: View {
    let url: URL
    let number: Int
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Theme.panel
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: 130, height: 195)
            .inkPanel(stroke: Theme.paper, shadow: Theme.red)

            Text("\(number)")
                .font(Theme.display(22))
                .monospacedDigit()
                .foregroundColor(Theme.yellow)
                .shadow(color: .black, radius: 0, x: 2, y: 2)
        }
        .task(id: url) {
            image = await PageImage.thumbnail(url)
        }
    }
}
