import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore
    @AppStorage("librarySort") private var sort = "recent"

    @State private var showingPicker = false
    @State private var reading: Book?
    @State private var renaming: Book?
    @State private var newTitle = ""
    @State private var deleting: Book?
    @State private var detail: Book?
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 18, alignment: .top)]

    // MARK: Derived lists

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sortedBooks: [Book] {
        let books = store.books.filter { $0.matches(query) }
        switch sort {
        case "title":
            return books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "added":
            return books.sorted { $0.addedAt > $1.addedAt }
        case "releaseNew":
            // Books with no known date go last.
            return books.sorted { ($0.releaseKey ?? Int.min) > ($1.releaseKey ?? Int.min) }
        case "releaseOld":
            return books.sorted { ($0.releaseKey ?? Int.max) < ($1.releaseKey ?? Int.max) }
        default:
            return books.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
        }
    }

    private var inProgress: [Book] {
        store.books
            .filter { $0.isStarted && !$0.isFinished }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
    }

    private var continueBook: Book? { inProgress.first }
    private var otherInProgress: [Book] { Array(inProgress.dropFirst()) }

    private var unread: [Book] {
        store.books
            .filter { !$0.isStarted }
            .sorted { $0.addedAt > $1.addedAt }
    }

    private var showsUnreadShelf: Bool {
        !unread.isEmpty && store.books.count >= 4 && unread.count < store.books.count
    }

    private var statsLine: String {
        let count = store.books.count
        let pages = store.books.reduce(0) { $0 + ($1.isStarted ? $1.currentPage + 1 : 0) }
        let comics = count == 1 ? "1 COMIC" : "\(count) COMICS"
        let read = pages == 1 ? "1 PAGE READ" : "\(pages) PAGES READ"
        return comics + "  •  " + read
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if store.books.isEmpty {
                        emptyState
                    } else if isSearching {
                        searchField
                        VStack(alignment: .leading, spacing: 16) {
                            CaptionBox(text: sortedBooks.count == 1 ? "1 match" : "\(sortedBooks.count) matches")
                            if sortedBooks.isEmpty {
                                Text("Nothing in the box matches that. Search looks at title, series, author, publisher and year.")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.paper.opacity(0.7))
                            } else {
                                LazyVGrid(columns: columns, spacing: 22) {
                                    ForEach(sortedBooks) { book in
                                        cell(book)
                                    }
                                }
                            }
                        }
                    } else {
                        searchField
                        if let book = continueBook {
                            hero(book)
                        }
                        if !otherInProgress.isEmpty {
                            shelf("Jump back in", books: otherInProgress)
                        }
                        if showsUnreadShelf {
                            shelf("New in the box", books: unread)
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            CaptionBox(text: "The whole box")
                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(sortedBooks) { book in
                                    cell(book)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .sheet(item: $detail) { book in
            BookDetailView(bookID: book.id)
                .environmentObject(store)
        }
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                store.importFiles(urls)
            }
        }
        .fullScreenCover(item: $reading) { book in
            ReaderView(bookID: book.id)
                .environmentObject(store)
        }
        .overlay(alignment: .bottom) {
            if let name = store.importingName {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(.black)
                    Text("ADDING \(name.uppercased())")
                        .font(Theme.caption(12))
                        .italic()
                        .lineLimit(1)
                        .foregroundColor(.black)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.yellow)
                .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2.5))
                .background(Rectangle().fill(Theme.red).offset(x: 4, y: 4))
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .alert(
            "Some files weren't added",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(
            "Rename",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("Title", text: $newTitle)
            Button("Save") {
                if let book = renaming { store.rename(book.id, to: newTitle) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete \(deleting?.title ?? "this comic")?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let book = deleting { store.delete(book.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("This removes it from Longbox. Your original file isn't touched.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LONGBOX")
                    .font(Theme.display(50))
                    .foregroundColor(Theme.yellow)
                    .shadow(color: Theme.red, radius: 0, x: 3, y: 3)
                    .padding(.trailing, 6)
                if !store.books.isEmpty {
                    Text(statsLine)
                        .font(Theme.caption(11))
                        .italic()
                        .kerning(0.5)
                        .monospacedDigit()
                        .foregroundColor(Theme.paper.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Menu {
                Picker("Sort by", selection: $sort) {
                    Text("Recently read").tag("recent")
                    Text("Recently added").tag("added")
                    Text("Title").tag("title")
                    Text("Release date, newest first").tag("releaseNew")
                    Text("Release date, oldest first").tag("releaseOld")
                }
            } label: {
                RoundIcon(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")

            Button {
                showingPicker = true
            } label: {
                RoundIcon(systemName: "plus")
            }
            .buttonStyle(PressDownStyle())
            .accessibilityLabel("Add comics")
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.black)
            TextField(
                "",
                text: $query,
                prompt: Text("Search title, author, publisher").foregroundColor(Color.black.opacity(0.45))
            )
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.black)
            .tint(Theme.red)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.black.opacity(0.6))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2.5))
        .background(Rectangle().fill(Theme.cyan).offset(x: 4, y: 4))
        .padding(.trailing, 4)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text("THE BOX IS EMPTY!")
                    .font(Theme.display(32))
                    .foregroundColor(.black)
                Text("Add .cbz or .cbr files from the Files app. Longbox keeps its own copy and remembers your page.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.black.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 46)
            .frame(maxWidth: 330)
            .background(SpeechBubble().fill(Theme.paper))
            .background(SpeechBubble().fill(Theme.yellow).offset(x: 6, y: 6))

            Button("ADD COMICS") {
                showingPicker = true
            }
            .buttonStyle(ComicButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    // MARK: Hero

    private func hero(_ book: Book) -> some View {
        Button {
            reading = book
        } label: {
            HStack(alignment: .center, spacing: 18) {
                CoverView(id: book.id)
                    .frame(width: 112)
                    .inkPanel(stroke: .black, shadow: .black)
                    .rotationEffect(.degrees(-4))
                    .padding(.leading, 4)

                VStack(alignment: .leading, spacing: 9) {
                    CaptionBox(text: "Continue reading", fill: Theme.paper, shadow: .black, size: 11)
                    Text(book.title)
                        .font(Theme.display(25))
                        .foregroundColor(.black)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    ChunkyProgress(value: book.progress)
                    Text("PAGE \(book.currentPage + 1) OF \(book.pageCount)")
                        .font(Theme.caption(12))
                        .monospacedDigit()
                        .foregroundColor(Color.black.opacity(0.75))
                    ComicPill(text: "READ!")
                        .padding(.top, 2)
                        .padding(.bottom, 3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    Theme.yellow
                    Halftone(color: Theme.orange, spacing: 10, maxRadius: 3.8)
                }
            )
            .inkPanel(corner: 6, line: 3, offset: 6, stroke: .black, shadow: Theme.red)
            .padding(.trailing, 6)
        }
        .buttonStyle(PressDownStyle())
    }

    // MARK: Shelves and cells

    private func shelf(_ title: String, books: [Book]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CaptionBox(text: title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 18) {
                    ForEach(books) { book in
                        cell(book)
                            .frame(width: 116)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, -16)
        }
    }

    private func cell(_ book: Book) -> some View {
        Button {
            detail = book
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                CoverView(id: book.id)
                    .inkPanel(stroke: Theme.paper, shadow: .black)
                    .overlay {
                        if book.isFinished {
                            StampBadge(text: "DONE")
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if !book.isStarted {
                            BurstBadge(text: "NEW!")
                                .offset(x: 12, y: -14)
                        }
                    }

                if book.isStarted && !book.isFinished {
                    ChunkyProgress(
                        value: book.progress,
                        fill: Theme.yellow,
                        track: Theme.panel,
                        border: Theme.paper,
                        height: 8
                    )
                }

                Text(book.title)
                    .font(.caption.weight(.bold))
                    .foregroundColor(Theme.paper)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(status(book))
                    .font(Theme.caption(10))
                    .kerning(0.4)
                    .monospacedDigit()
                    .foregroundColor(Theme.paper.opacity(0.6))
            }
        }
        .buttonStyle(PressDownStyle())
        .contextMenu {
            Button {
                reading = book
            } label: {
                Label(book.isStarted ? "Continue reading" : "Read", systemImage: "book")
            }
            Button {
                newTitle = book.title
                renaming = book
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            if book.isStarted {
                Button {
                    store.markUnread(book.id)
                } label: {
                    Label("Mark as unread", systemImage: "arrow.uturn.backward")
                }
            }
            Button(role: .destructive) {
                deleting = book
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func status(_ book: Book) -> String {
        if book.isFinished { return "FINISHED" }
        if book.isStarted { return "PAGE \(book.currentPage + 1) OF \(book.pageCount)" }
        if let year = book.year { return "\(String(year))  •  \(book.pageCount) PAGES" }
        return "\(book.pageCount) PAGES"
    }
}

/// A book's cover at the standard 2:3 comic proportion. Callers add the border.
struct CoverView: View {
    let id: UUID
    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Theme.panel
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundColor(Theme.paper.opacity(0.5))
                    }
                }
            }
            .clipped()
            .task(id: id) {
                let path = Storage.cover(for: id).path
                image = await Task.detached(priority: .utility) {
                    UIImage(contentsOfFile: path)
                }.value
            }
    }
}
