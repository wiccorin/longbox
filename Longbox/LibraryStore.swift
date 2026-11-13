import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var importingName: String?
    @Published var errorMessage: String?
    /// Days with any reading, as "yyyy-MM-dd".
    @Published private(set) var readingDays: Set<String> = []

    private let saveQueue = DispatchQueue(label: "longbox.library.save", qos: .utility)
    private var pending: [(url: URL, fromDropFolder: Bool)] = []
    private var currentImportPath: String?
    private var importing = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    init() {
        Storage.prepare()
        load()
        readingDays = Set(UserDefaults.standard.stringArray(forKey: "readingDays") ?? [])
    }

    func book(_ id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    // MARK: Series

    func series(_ key: String) -> [Book] {
        SeriesOrder.sorted(books.filter { $0.seriesKey == key })
    }

    /// The issue that follows this one in its series, if there is one.
    func nextInSeries(after book: Book) -> Book? {
        guard let key = book.seriesKey else { return nil }
        let ordered = series(key)
        guard let index = ordered.firstIndex(where: { $0.id == book.id }), index + 1 < ordered.count else {
            return nil
        }
        return ordered[index + 1]
    }

    // MARK: Import

    func importFiles(_ urls: [URL]) {
        enqueue(urls.map { ($0, false) })
    }

    /// Picks up comics dropped into the Longbox folder (Files app, or USB from a computer).
    func scanDropFolder() {
        let fm = FileManager.default
        let folder = Storage.dropFolder
        Storage.prepareDropFolder()

        var candidates: [URL] = []
        for directory in [folder, folder.appendingPathComponent("Inbox", isDirectory: true)] {
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in items {
                guard ["cbz", "cbr", "zip", "rar"].contains(url.pathExtension.lowercased()) else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                // A file still being copied over keeps changing; leave it for the next pass.
                if let modified = values?.contentModificationDate, Date().timeIntervalSince(modified) < 3 {
                    continue
                }
                candidates.append(url)
            }
        }
        candidates.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        enqueue(candidates.map { ($0, true) })
    }

    private func enqueue(_ items: [(URL, Bool)]) {
        for item in items {
            let path = Storage.canonicalPath(item.0)
            if path == currentImportPath { continue }
            if pending.contains(where: { Storage.canonicalPath($0.url) == path }) { continue }
            pending.append((item.0, item.1))
        }
        runImports()
    }

    private func runImports() {
        guard !importing, !pending.isEmpty else { return }
        importing = true
        Task {
            var failures: [String] = []
            while !pending.isEmpty {
                let item = pending.removeFirst()
                let url = item.url
                currentImportPath = Storage.canonicalPath(url)
                importingName = url.deletingPathExtension().lastPathComponent
                do {
                    let book = try await Task.detached(priority: .userInitiated) {
                        try Importer.importBook(from: url)
                    }.value
                    books.append(book)
                    save()
                    if item.fromDropFolder {
                        // Longbox has its own copy now.
                        try? FileManager.default.removeItem(at: url)
                    }
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    if item.fromDropFolder {
                        Storage.setAside(url)
                    }
                }
            }
            currentImportPath = nil
            importingName = nil
            importing = false
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n")
            }
        }
    }

    // MARK: Reading

    func setPage(_ page: Int, for id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(page, 0), max(books[index].pageCount - 1, 0))
        books[index].currentPage = clamped
        books[index].lastReadAt = Date()
        save()
        noteReadingToday()
    }

    func setMode(_ mode: ReadingMode, for id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].mode = mode
        save()
    }

    func markUnread(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].currentPage = 0
        books[index].lastReadAt = nil
        save()
    }

    func addReadingTime(_ seconds: Double, for id: UUID) {
        guard seconds > 0 else { return }
        update(id) { book in
            book.secondsRead = (book.secondsRead ?? 0) + seconds
        }
    }

    // MARK: Streak

    private func noteReadingToday() {
        let today = Self.dayFormatter.string(from: Date())
        guard !readingDays.contains(today) else { return }
        readingDays.insert(today)
        UserDefaults.standard.set(Array(readingDays), forKey: "readingDays")
    }

    /// Days in a row with reading, counting today or, if today is still open, up to yesterday.
    var streak: Int {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if !readingDays.contains(Self.dayFormatter.string(from: day)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  readingDays.contains(Self.dayFormatter.string(from: yesterday))
            else { return 0 }
            day = yesterday
        }
        var count = 0
        while readingDays.contains(Self.dayFormatter.string(from: day)) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    // MARK: Details

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { $0.title = trimmed }
    }

    /// Applies any edit to a book's details and saves.
    func update(_ id: UUID, _ change: (inout Book) -> Void) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        change(&books[index])
        save()
    }

    /// Marks a chapter start. The first marker also adds one at page 1 so nothing is left uncovered.
    func addChapter(at page: Int, for id: UUID) {
        update(id) { book in
            var list = book.chapters ?? []
            guard !list.contains(where: { $0.startPage == page }) else { return }
            if list.isEmpty && page > 0 {
                list.append(Chapter(title: "", startPage: 0))
            }
            list.append(Chapter(title: "", startPage: page))
            list.sort { $0.startPage < $1.startPage }
            book.chapters = list
        }
    }

    func removeChapter(startPage: Int, for id: UUID) {
        update(id) { book in
            var list = book.chapters ?? []
            list.removeAll { $0.startPage == startPage }
            book.chapters = list.isEmpty ? nil : list
        }
    }

    func delete(_ id: UUID) {
        books.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Storage.folder(for: id))
        try? FileManager.default.removeItem(at: Storage.cover(for: id))
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Storage.libraryFile),
              let saved = try? JSONDecoder().decode([Book].self, from: data)
        else { return }
        books = saved

        var changed = false

        // Libraries from earlier builds have no release year; recover it from the title.
        for index in books.indices where books[index].year == nil {
            if let year = TitleParser.year(in: books[index].title) {
                books[index].year = year
                changed = true
            }
        }

        // One time only: work out series and issue numbers for books added before stacks existed.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "seriesBackfillDone") {
            for index in books.indices where books[index].seriesKey == nil {
                if let parsed = TitleParser.seriesAndNumber(in: books[index].title) {
                    books[index].series = parsed.series
                    books[index].number = parsed.number
                    changed = true
                }
            }
            defaults.set(true, forKey: "seriesBackfillDone")
        }

        if changed { save() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        let file = Storage.libraryFile
        saveQueue.async {
            try? data.write(to: file, options: .atomic)
        }
    }
}
