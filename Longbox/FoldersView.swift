import SwiftUI

/// The Folders tab: collections you make yourself.
struct FoldersView: View {
    @EnvironmentObject private var store: LibraryStore

    @State private var open: ComicFolder?
    @State private var naming = false
    @State private var name = ""
    @State private var renaming: ComicFolder?
    @State private var deleting: ComicFolder?

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 20, alignment: .top)]

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if store.folders.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: columns, spacing: 26) {
                            ForEach(store.sortedFolders) { folder in
                                folderCell(folder)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .sheet(item: $open) { folder in
            FolderView(folderID: folder.id)
                .environmentObject(store)
        }
        .alert(renaming == nil ? "New folder" : "Rename folder", isPresented: $naming) {
            TextField("Folder name", text: $name)
            Button(renaming == nil ? "Create" : "Save") {
                if let folder = renaming {
                    store.renameFolder(folder.id, to: name)
                } else {
                    store.createFolder(named: name)
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Delete the folder \(deleting?.name ?? "")?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete folder", role: .destructive) {
                if let folder = deleting { store.deleteFolder(folder.id) }
                deleting = nil
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: {
            Text("The comics in it stay in your box.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("FOLDERS")
                    .font(Theme.display(50))
                    .foregroundColor(Theme.yellow)
                    .shadow(color: Theme.red, radius: 0, x: 3, y: 3)
                    .padding(.trailing, 6)
                if !store.folders.isEmpty {
                    Text(store.folders.count == 1 ? "1 FOLDER" : "\(store.folders.count) FOLDERS")
                        .font(Theme.caption(11))
                        .italic()
                        .kerning(0.5)
                        .monospacedDigit()
                        .foregroundColor(Theme.paper.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Button {
                startNew()
            } label: {
                RoundIcon(systemName: "plus")
            }
            .buttonStyle(PressDownStyle())
            .accessibilityLabel("New folder")
        }
    }

    private func startNew() {
        renaming = nil
        name = ""
        naming = true
    }

    private var emptyState: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text("NO FOLDERS YET!")
                    .font(Theme.display(32))
                    .foregroundColor(.black)
                Text("Make a folder here, then long-press any comic or series in the Box and choose Add to folder.")
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

            Button("NEW FOLDER") {
                startNew()
            }
            .buttonStyle(ComicButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    /// A folder drawn as a comic box: covers standing up behind the front of the box.
    private func folderCell(_ folder: ComicFolder) -> some View {
        let books = store.books(in: folder.id)
        let covers = Array(books.prefix(3))
        return Button {
            open = folder
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Color.clear
                    .aspectRatio(1.15, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            ZStack(alignment: .bottom) {
                                HStack(alignment: .top, spacing: -geo.size.width * 0.12) {
                                    ForEach(Array(covers.enumerated()), id: \.offset) { index, book in
                                        CoverView(id: book.id)
                                            .frame(width: geo.size.width * 0.38)
                                            .inkPanel(corner: 2, line: 2, offset: 0, stroke: .black, shadow: .clear)
                                            .rotationEffect(.degrees(Double(index - 1) * 5))
                                    }
                                }
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)

                                ZStack {
                                    Theme.cyan
                                    Capsule()
                                        .fill(Theme.ink)
                                        .frame(width: geo.size.width * 0.3, height: 12)
                                }
                                .frame(width: geo.size.width, height: geo.size.height * 0.5)
                                .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2.5))
                                .background(Rectangle().fill(Color.black).offset(x: 4, y: 4))
                            }
                        }
                    }

                Text(folder.name)
                    .font(Theme.display(20))
                    .foregroundColor(Theme.paper)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(books.count == 1 ? "1 COMIC" : "\(books.count) COMICS")
                    .font(Theme.caption(10))
                    .kerning(0.4)
                    .monospacedDigit()
                    .foregroundColor(Theme.paper.opacity(0.6))
            }
        }
        .buttonStyle(PressDownStyle())
        .contextMenu {
            Button {
                renaming = folder
                name = folder.name
                naming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleting = folder
            } label: {
                Label("Delete folder", systemImage: "trash")
            }
        }
    }
}

/// The comics inside one folder.
struct FolderView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID

    @State private var reading: Book?

    private let columns = [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 18, alignment: .top)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                Halftone(color: Theme.panel).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack {
                            CaptionBox(text: "Folder", shadow: Theme.cyan)
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                RoundIcon(systemName: "xmark")
                            }
                            .buttonStyle(PressDownStyle())
                            .accessibilityLabel("Close")
                        }

                        let books = store.books(in: folderID)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.folder(folderID)?.name ?? "Folder")
                                .font(Theme.display(34))
                                .foregroundColor(Theme.yellow)
                                .shadow(color: Theme.red, radius: 0, x: 3, y: 3)
                            Text(books.count == 1 ? "1 COMIC" : "\(books.count) COMICS")
                                .font(Theme.caption(11))
                                .italic()
                                .kerning(0.5)
                                .monospacedDigit()
                                .foregroundColor(Theme.paper.opacity(0.7))
                        }

                        if books.isEmpty {
                            Text("Nothing in this folder yet. In the Box, long-press a comic or a series and choose Add to folder.")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Theme.paper.opacity(0.55))
                        } else {
                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(books) { book in
                                    NavigationLink(value: book.id) {
                                        cell(book)
                                    }
                                    .buttonStyle(PressDownStyle())
                                    .contextMenu {
                                        Button {
                                            reading = book
                                        } label: {
                                            Label(book.isStarted ? "Continue reading" : "Read", systemImage: "book")
                                        }
                                        Button(role: .destructive) {
                                            store.remove([book.id], from: folderID)
                                        } label: {
                                            Label("Remove from folder", systemImage: "folder.badge.minus")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                BookDetailView(bookID: id, siblings: store.books(in: folderID).map { $0.id })
                    .environmentObject(store)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(item: $reading) { book in
            ReaderHost(bookID: book.id)
                .environmentObject(store)
        }
    }

    private func cell(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(id: book.id)
                .inkPanel(stroke: Theme.paper, shadow: .black)
                .overlay {
                    if book.isFinished {
                        StampBadge(text: "DONE")
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

    private func status(_ book: Book) -> String {
        if book.isFinished { return "FINISHED" }
        if book.isStarted { return "PAGE \(book.currentPage + 1) OF \(book.pageCount)" }
        return "\(book.pageCount) PAGES"
    }
}
