import SwiftUI

/// Everything about one comic: details, description and chapters.
struct BookDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let bookID: UUID

    @State private var reading = false
    @State private var editing = false
    @State private var lookingUp = false

    private var book: Book? { store.book(bookID) }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            Halftone(color: Theme.panel).ignoresSafeArea()

            if let book {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        closeRow
                        masthead(book)
                        facts(book)
                        description(book)
                        actions
                        chapters(book)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 40)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $reading) {
            ReaderView(bookID: bookID)
                .environmentObject(store)
        }
        .sheet(isPresented: $editing) {
            EditDetailsView(bookID: bookID)
                .environmentObject(store)
        }
        .sheet(isPresented: $lookingUp) {
            LookupView(bookID: bookID)
                .environmentObject(store)
        }
    }

    // MARK: Sections

    private var closeRow: some View {
        HStack {
            CaptionBox(text: "Details", shadow: Theme.cyan)
            Spacer()
            Button {
                dismiss()
            } label: {
                RoundIcon(systemName: "xmark")
            }
            .buttonStyle(PressDownStyle())
            .accessibilityLabel("Close")
        }
    }

    private func masthead(_ book: Book) -> some View {
        HStack(alignment: .center, spacing: 18) {
            CoverView(id: book.id)
                .frame(width: 118)
                .inkPanel(stroke: .black, shadow: .black)
                .rotationEffect(.degrees(-4))
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 9) {
                Text(book.title)
                    .font(Theme.display(26))
                    .foregroundColor(.black)
                    .lineLimit(4)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)
                if let year = book.year {
                    CaptionBox(text: String(year), fill: Theme.paper, shadow: .black, size: 11)
                }
                if book.isStarted && !book.isFinished {
                    ChunkyProgress(value: book.progress)
                    Text("PAGE \(book.currentPage + 1) OF \(book.pageCount)")
                        .font(Theme.caption(12))
                        .monospacedDigit()
                        .foregroundColor(Color.black.opacity(0.75))
                }
                Button(readLabel(book)) {
                    if book.isFinished {
                        store.setPage(0, for: bookID)
                    }
                    reading = true
                }
                .buttonStyle(ComicButtonStyle(fill: Theme.red, shadow: .black, textColor: Theme.paper, size: 22))
                .padding(.top, 2)
                .padding(.bottom, 4)
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

    private func readLabel(_ book: Book) -> String {
        if book.isFinished { return "READ AGAIN" }
        if book.isStarted { return "CONTINUE" }
        return "READ!"
    }

    private func facts(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            fact("Written by", book.writer)
            fact("Publisher", book.publisher)
            fact("Released", book.releaseText)
            if let series = book.series, !series.isEmpty {
                fact("Series", series)
            }
            fact("Length", "\(book.pageCount) pages")
        }
    }

    private func fact(_ label: String, _ value: String?) -> some View {
        let known = !(value ?? "").isEmpty
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label.uppercased())
                .font(Theme.caption(11))
                .italic()
                .kerning(0.6)
                .foregroundColor(Theme.yellow)
                .frame(width: 96, alignment: .leading)
            Text(known ? (value ?? "") : "Unknown")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.paper.opacity(known ? 1 : 0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func description(_ book: Book) -> some View {
        if let summary = book.summary, !summary.isEmpty {
            Text(summary)
                .font(.subheadline)
                .foregroundColor(.black)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.paper)
                .inkPanel(corner: 2, line: 2.5, offset: 5, stroke: .black, shadow: Theme.cyan)
                .padding(.trailing, 5)
        } else {
            Text("No description yet. Use Find details to look this comic up, or Edit to write your own.")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Theme.paper.opacity(0.55))
        }
    }

    private var actions: some View {
        HStack(spacing: 16) {
            Button("FIND DETAILS") {
                lookingUp = true
            }
            .buttonStyle(ComicButtonStyle(size: 18))
            Button("EDIT") {
                editing = true
            }
            .buttonStyle(ComicButtonStyle(fill: Theme.paper, shadow: Theme.cyan, size: 18))
        }
    }

    private func chapters(_ book: Book) -> some View {
        let list = book.chapterList
        let current = book.isStarted ? book.currentChapterIndex : nil
        return VStack(alignment: .leading, spacing: 14) {
            CaptionBox(text: list.isEmpty ? "Chapters" : "\(list.count) chapters")
            if list.isEmpty {
                Text("This file has no chapter markers. While reading, open the menu in the top right and choose Mark chapter start here to add your own.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Theme.paper.opacity(0.55))
            } else {
                ForEach(Array(list.enumerated()), id: \.offset) { index, chapter in
                    let lastPage = (index + 1 < list.count ? list[index + 1].startPage : book.pageCount)
                    let isRead = book.isFinished || (current != nil && index < (current ?? 0))
                    let isCurrent = !book.isFinished && current == index
                    chapterRow(
                        number: index + 1,
                        title: chapter.displayTitle(index),
                        pages: "PAGES \(chapter.startPage + 1) TO \(max(lastPage, chapter.startPage + 1))",
                        isRead: isRead,
                        isCurrent: isCurrent
                    ) {
                        store.setPage(chapter.startPage, for: bookID)
                        reading = true
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            store.removeChapter(startPage: chapter.startPage, for: bookID)
                        } label: {
                            Label("Remove chapter marker", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
        }
    }

    private func chapterRow(
        number: Int,
        title: String,
        pages: String,
        isRead: Bool,
        isCurrent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(Theme.display(22))
                    .monospacedDigit()
                    .foregroundColor(.black)
                    .frame(width: 42, height: 42)
                    .background(isCurrent ? Theme.yellow : Theme.paper)
                    .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 2))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Theme.paper)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(pages)
                        .font(Theme.caption(10))
                        .kerning(0.4)
                        .monospacedDigit()
                        .foregroundColor(Theme.paper.opacity(0.6))
                }
                Spacer(minLength: 0)

                if isCurrent {
                    CaptionBox(text: "Reading", shadow: .black, size: 10)
                } else if isRead {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(Theme.paper)
                        .accessibilityLabel("Read")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .inkPanel(
                corner: 4,
                line: 2,
                offset: 4,
                stroke: isCurrent ? Theme.yellow : Theme.paper.opacity(0.35),
                shadow: .black
            )
            .padding(.trailing, 4)
            // Chapters you've already read step back.
            .opacity(isRead ? 0.4 : 1)
        }
        .buttonStyle(PressDownStyle())
    }
}

// MARK: Edit

struct EditDetailsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let bookID: UUID

    @State private var loaded = false
    @State private var title = ""
    @State private var writer = ""
    @State private var publisher = ""
    @State private var series = ""
    @State private var year = ""
    @State private var month = 0
    @State private var summary = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                }
                Section("Details") {
                    TextField("Author", text: $writer)
                    TextField("Publisher", text: $publisher)
                    TextField("Series", text: $series)
                    TextField("Year", text: $year)
                        .keyboardType(.numberPad)
                    Picker("Month", selection: $month) {
                        Text("Not set").tag(0)
                        ForEach(1...12, id: \.self) { number in
                            Text(DateFormatter().monthSymbols[number - 1]).tag(number)
                        }
                    }
                }
                Section("Description") {
                    TextEditor(text: $summary)
                        .frame(minHeight: 160)
                }
            }
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard !loaded, let book = store.book(bookID) else { return }
            loaded = true
            title = book.title
            writer = book.writer ?? ""
            publisher = book.publisher ?? ""
            series = book.series ?? ""
            year = book.year.map { String($0) } ?? ""
            month = book.month ?? 0
            summary = book.summary ?? ""
        }
    }

    private func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() {
        let newTitle = clean(title)
        let newWriter = clean(writer)
        let newPublisher = clean(publisher)
        let newSeries = clean(series)
        let newYear = Int(year.trimmingCharacters(in: .whitespacesAndNewlines))
        let newMonth = month == 0 ? nil : month
        let newSummary = clean(summary)
        store.update(bookID) { book in
            if let newTitle { book.title = newTitle }
            book.writer = newWriter
            book.publisher = newPublisher
            book.series = newSeries
            book.year = newYear
            book.month = newYear == nil ? nil : newMonth
            book.summary = newSummary
        }
    }
}

// MARK: Lookup

struct LookupView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let bookID: UUID

    @State private var query = ""
    @State private var results: [MetadataMatch] = []
    @State private var searching = false
    @State private var message: String?
    @State private var started = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Title to look up", text: $query)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { runSearch() }
                        Button("Search") { runSearch() }
                            .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } footer: {
                    Text("Searches Google Books. Only this search text is sent. Pick a match to fill in author, publisher, release date and description.")
                }

                if searching {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Searching")
                            .foregroundStyle(.secondary)
                    }
                } else if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { match in
                        Button {
                            apply(match)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(match.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text(subtitle(match))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let summary = match.summary {
                                    Text(summary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Find details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            query = store.book(bookID).map { TitleParser.clean($0.title) } ?? ""
            runSearch()
        }
    }

    private func subtitle(_ match: MetadataMatch) -> String {
        var parts: [String] = []
        if let authors = match.authors { parts.append(authors) }
        if let publisher = match.publisher { parts.append(publisher) }
        if let year = match.year { parts.append(String(year)) }
        return parts.isEmpty ? "No details listed" : parts.joined(separator: "  •  ")
    }

    private func runSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        message = nil
        Task { @MainActor in
            do {
                let found = try await MetadataLookup.search(text)
                results = found
                message = found.isEmpty ? "No matches. Try a shorter title." : nil
            } catch {
                results = []
                message = "Couldn't search: \(error.localizedDescription)"
            }
            searching = false
        }
    }

    private func apply(_ match: MetadataMatch) {
        store.update(bookID) { book in
            if let authors = match.authors { book.writer = authors }
            if let publisher = match.publisher { book.publisher = publisher }
            if let year = match.year {
                book.year = year
                book.month = match.month
            }
            if let summary = match.summary { book.summary = summary }
        }
    }
}
