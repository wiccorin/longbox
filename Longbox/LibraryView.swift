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

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 14, alignment: .top)]

    private var sortedBooks: [Book] {
        switch sort {
        case "title":
            return store.books.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case "added":
            return store.books.sorted { $0.addedAt > $1.addedAt }
        default:
            return store.books.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
        }
    }

    private var continueBook: Book? {
        store.books
            .filter { $0.isStarted && !$0.isFinished }
            .max { ($0.lastReadAt ?? .distantPast) < ($1.lastReadAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.books.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if let book = continueBook {
                                continueCard(book)
                            }
                            LazyVGrid(columns: columns, spacing: 18) {
                                ForEach(sortedBooks) { book in
                                    cell(book)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Longbox")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Sort by", selection: $sort) {
                            Text("Recently read").tag("recent")
                            Text("Recently added").tag("added")
                            Text("Title").tag("title")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingPicker = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add comics")
                }
            }
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
                    Text("Adding \(name)")
                        .lineLimit(1)
                        .font(.footnote.weight(.medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .padding(.horizontal, 24)
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

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Your box is empty")
                .font(.title3.weight(.semibold))
            Text("Add .cbz or .cbr files from the Files app. Longbox keeps its own copy and remembers your page.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button {
                showingPicker = true
            } label: {
                Label("Add comics", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.black)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func continueCard(_ book: Book) -> some View {
        Button {
            reading = book
        } label: {
            HStack(spacing: 14) {
                CoverView(id: book.id)
                    .frame(width: 74)
                VStack(alignment: .leading, spacing: 6) {
                    Text("CONTINUE READING")
                        .font(.caption2.weight(.bold))
                        .kerning(0.8)
                        .foregroundStyle(Theme.accent)
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("Page \(book.currentPage + 1) of \(book.pageCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    ProgressView(value: book.progress)
                        .tint(Theme.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func cell(_ book: Book) -> some View {
        Button {
            reading = book
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoverView(id: book.id)
                    .overlay(alignment: .bottom) {
                        if book.isStarted && !book.isFinished {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(Theme.accent)
                                    .frame(width: geo.size.width * book.progress, height: 3)
                                    .frame(maxHeight: .infinity, alignment: .bottom)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(book.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(status(book))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
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
        if book.isFinished { return "Finished" }
        if book.isStarted { return "\(book.currentPage + 1) of \(book.pageCount)" }
        return "\(book.pageCount) pages"
    }
}

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
                        Theme.card
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: id) {
                let path = Storage.cover(for: id).path
                image = await Task.detached(priority: .utility) {
                    UIImage(contentsOfFile: path)
                }.value
            }
    }
}
