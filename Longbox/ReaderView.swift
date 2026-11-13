import SwiftUI

/// Hosts the reader and lets it hand over to another book, such as the next issue.
struct ReaderHost: View {
    @State private var currentID: UUID

    init(bookID: UUID) {
        _currentID = State(initialValue: bookID)
    }

    var body: some View {
        ReaderView(bookID: currentID) { next in
            currentID = next
        }
        .id(currentID)
    }
}

struct ReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("trimMargins") private var trim = false
    @AppStorage("panelView") private var guided = false
    @AppStorage("landscapeSpreads") private var spreads = true

    let bookID: UUID
    let openBook: (UUID) -> Void

    @State private var page = 0
    @State private var ready = false
    @State private var showChrome = true
    @State private var showEnd = false
    @State private var urls: [URL] = []
    /// Width over height of each untrimmed page.
    @State private var aspects: [CGFloat]?
    @State private var trims: [CGRect]?
    @State private var scrub: Double = 0
    @State private var scrubbing = false
    @State private var saveTask: Task<Void, Never>?
    /// When the current stretch of reading began. Nil while the app is in the background.
    @State private var sessionStart: Date?

    private var book: Book? { store.book(bookID) }

    private struct PrepKey: Equatable {
        var mode: ReadingMode
        var trim: Bool
        var paired: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height

            ZStack {
                Color.black.ignoresSafeArea()

                if let book, ready {
                    let paired = book.mode != .vertical && landscape && spreads && !guided
                    let units = Spreads.units(count: urls.count, aspects: paired ? aspects : nil)
                    let lastStart = book.mode == .vertical ? urls.count - 1 : (units.last?.first ?? 0)
                    let atEnd = !urls.isEmpty && page >= lastStart

                    pages(book, paired: paired, units: units)
                        .ignoresSafeArea()
                        .task(id: PrepKey(mode: book.mode, trim: trim, paired: paired)) {
                            await prepare(book, paired: paired)
                        }

                    if showChrome && !showEnd {
                        chrome(book)
                            .transition(.opacity)
                    }

                    if atEnd && !showEnd {
                        finishButton(book)
                    }

                    if showEnd {
                        endScreen(book)
                            .transition(.opacity)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
                sessionStart = Date()
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
            guard ready else { return }
            if phase == .active {
                if sessionStart == nil { sessionStart = Date() }
            } else {
                saveTask?.cancel()
                store.setPage(page, for: bookID)
                commitReadingTime()
            }
        }
        .onDisappear {
            saveTask?.cancel()
            if ready {
                store.setPage(page, for: bookID)
                commitReadingTime()
            }
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func pages(_ book: Book, paired: Bool, units: [[Int]]) -> some View {
        if book.mode == .vertical {
            if let shown = stripAspects() {
                StripReader(urls: urls, aspects: shown, trim: trim, page: $page, onTap: toggleChrome)
            } else {
                loading(trim ? "TRIMMING MARGINS" : "GETTING PAGES READY")
            }
        } else if paired && aspects == nil {
            loading("GETTING PAGES READY")
        } else {
            PagedReader(
                urls: urls,
                units: units,
                rightToLeft: book.mode == .rightToLeft,
                trim: trim,
                guided: guided,
                page: $page,
                onCenterTap: toggleChrome,
                onPastEnd: { finish(book) }
            )
        }
    }

    /// Page shapes for vertical mode, after trimming if that's on. Nil until they're worked out.
    private func stripAspects() -> [CGFloat]? {
        guard let aspects, aspects.count == urls.count else { return nil }
        guard trim else { return aspects }
        guard let trims, trims.count == urls.count else { return nil }
        return zip(aspects, trims).map { aspect, rect in
            rect.height > 0 ? aspect * rect.width / rect.height : aspect
        }
    }

    private func prepare(_ book: Book, paired: Bool) async {
        let pageURLs = urls
        if (book.mode == .vertical || paired) && aspects == nil {
            aspects = await PageImage.aspects(pageURLs)
        }
        if book.mode == .vertical && trim && trims == nil {
            let file = Storage.folder(for: book.id).appendingPathComponent("trim.json")
            trims = await PageImage.trimRects(pageURLs, cacheFile: file)
        }
    }

    private func loading(_ text: String) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text(text)
                .font(Theme.caption(11))
                .italic()
                .kerning(0.6)
                .foregroundColor(Theme.paper.opacity(0.7))
        }
    }

    // MARK: Session

    /// Banks the time since the session began. Only counts while the reader is on screen.
    private func commitReadingTime() {
        guard let start = sessionStart else { return }
        sessionStart = nil
        store.addReadingTime(Date().timeIntervalSince(start), for: bookID)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showChrome.toggle()
        }
    }

    private func finish(_ book: Book) {
        saveTask?.cancel()
        store.setPage(book.pageCount - 1, for: bookID)
        withAnimation(.easeOut(duration: 0.2)) {
            showEnd = true
        }
    }

    // MARK: Chrome

    private func chrome(_ book: Book) -> some View {
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
                Toggle(isOn: $guided) {
                    Label("Panel view", systemImage: "rectangle.split.2x2")
                }
                Toggle(isOn: $trim) {
                    Label("Trim margins", systemImage: "crop")
                }
                Toggle(isOn: $spreads) {
                    Label("Two pages in landscape", systemImage: "book")
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
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Theme.yellow))
                    .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Reading options")
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
            HStack(alignment: .center, spacing: 12) {
                CaptionBox(text: "Page \(shown + 1) of \(book.pageCount)", shadow: .black)
                Spacer(minLength: 0)
                TimelineView(.periodic(from: Date(), by: 1)) { context in
                    Text("TIME READING  " + ReadingTime.clock(totalSeconds(book, at: context.date)))
                        .font(Theme.caption(11))
                        .italic()
                        .kerning(0.5)
                        .monospacedDigit()
                        .foregroundColor(Theme.paper.opacity(0.8))
                }
            }
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

    private func totalSeconds(_ book: Book, at date: Date) -> Double {
        let live = sessionStart.map { max(date.timeIntervalSince($0), 0) } ?? 0
        return (book.secondsRead ?? 0) + live
    }

    // MARK: The end

    private func finishButton(_ book: Book) -> some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                Button("FINISH!") {
                    finish(book)
                }
                .buttonStyle(ComicButtonStyle(fill: Theme.red, shadow: .black, textColor: Theme.paper, size: 20))
            }
        }
        .padding(.trailing, 20)
        .padding(.bottom, showChrome ? 124 : 28)
    }

    private func endScreen(_ book: Book) -> some View {
        let next = store.nextInSeries(after: book)
        let streak = store.streak
        return ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Text("THE END!")
                        .font(Theme.display(54))
                        .foregroundColor(.black)
                        .frame(width: 250, height: 250)
                        .background(Burst(points: 16, inner: 0.8).fill(Theme.yellow))
                        .background(Burst(points: 16, inner: 0.8).fill(Theme.red).offset(x: 7, y: 7))
                        .rotationEffect(.degrees(-7))
                        .padding(.top, 8)

                    Text(book.title)
                        .font(Theme.display(26))
                        .foregroundColor(Theme.paper)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    HStack(spacing: 14) {
                        endStat("TIME", ReadingTime.words(totalSeconds(book, at: Date())).uppercased())
                        endStat("PAGES", "\(book.pageCount)")
                        if streak >= 1 {
                            endStat("STREAK", streak == 1 ? "1 DAY" : "\(streak) DAYS")
                        }
                    }

                    if let next {
                        VStack(alignment: .leading, spacing: 12) {
                            CaptionBox(text: "Up next")
                            Button {
                                commitReadingTime()
                                openBook(next.id)
                            } label: {
                                HStack(spacing: 14) {
                                    CoverView(id: next.id)
                                        .frame(width: 70)
                                        .inkPanel(stroke: .black, shadow: .black)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(next.title)
                                            .font(Theme.display(21))
                                            .foregroundColor(.black)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                        ComicPill(text: "READ NEXT")
                                            .padding(.bottom, 3)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .background(Theme.yellow)
                                .inkPanel(corner: 6, line: 3, offset: 6, stroke: .black, shadow: Theme.red)
                                .padding(.trailing, 6)
                            }
                            .buttonStyle(PressDownStyle())
                        }
                    }

                    Button("BACK TO THE BOX") {
                        dismiss()
                    }
                    .buttonStyle(ComicButtonStyle(fill: Theme.paper, shadow: Theme.cyan, size: 20))
                    .padding(.top, 4)

                    Button("Keep looking at the last page") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            showEnd = false
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.7))
                    .padding(.bottom, 20)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func endStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.display(24))
                .monospacedDigit()
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Theme.caption(10))
                .kerning(0.6)
                .foregroundColor(Color.black.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(Theme.paper)
        .inkPanel(corner: 4, line: 2.5, offset: 4, stroke: .black, shadow: Theme.cyan)
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
