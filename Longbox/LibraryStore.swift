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
    private var pending: [(url: URL, fromDropFolder: Bool, folderName: String?)] = []
    @Published private(set) var folders: [ComicFolder] = []
    @Published private(set) var clips: [Clip] = []
    /// Seconds read per day, keyed "yyyy-MM-dd".
    @Published private(set) var dailySeconds: [String: Double] = [:]
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
        dailySeconds = (UserDefaults.standard.dictionary(forKey: "dailySeconds") as? [String: Double]) ?? [:]
        if let data = try? Data(contentsOf: Storage.clipsFile),
           let saved = try? JSONDecoder().decode([Clip].self, from: data) {
            clips = saved
        }
        if let data = try? Data(contentsOf: Storage.foldersFile),
           let saved = try? JSONDecoder().decode([ComicFolder].self, from: data) {
            folders = saved
        }
    }

    // MARK: Clippings

    /// Saves a page, or one panel of it, to the clippings.
    /// `rect` is a unit rectangle; `trimmed` says it was measured on the margin-trimmed page.
    func addClip(bookID: UUID, page: Int, rect: CGRect?, trimmed: Bool) {
        guard let book = book(bookID), book.pages.indices.contains(page) else { return }
        let source = Storage.folder(for: bookID).appendingPathComponent(book.pages[page])
        let clip = Clip(id: UUID(), bookID: bookID, bookTitle: book.title, page: page, createdAt: Date())
        let target = Storage.clipImage(clip.id)
        Task {
            let saved = await Task.detached(priority: .userInitiated) { () -> Bool in
                guard let decoded = PageImage.downsampled(source, shortSide: 1400),
                      var image = decoded.cgImage
                else { return false }
                if var unit = rect {
                    if trimmed {
                        let trim = PageImage.trimRect(for: source)
                        unit = CGRect(
                            x: trim.minX + unit.minX * trim.width,
                            y: trim.minY + unit.minY * trim.height,
                            width: unit.width * trim.width,
                            height: unit.height * trim.height
                        )
                    }
                    let crop = CGRect(
                        x: unit.minX * CGFloat(image.width),
                        y: unit.minY * CGFloat(image.height),
                        width: unit.width * CGFloat(image.width),
                        height: unit.height * CGFloat(image.height)
                    ).integral
                    if let cropped = image.cropping(to: crop) {
                        image = cropped
                    }
                }
                guard let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.88) else { return false }
                return (try? data.write(to: target, options: .atomic)) != nil
            }.value
            if saved {
                clips.insert(clip, at: 0)
                saveClips()
            }
        }
    }

    func deleteClip(_ id: UUID) {
        clips.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: Storage.clipImage(id))
        saveClips()
    }

    private func saveClips() {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        let file = Storage.clipsFile
        saveQueue.async {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Stats

    func seconds(on date: Date) -> Double {
        dailySeconds[Self.dayFormatter.string(from: date)] ?? 0
    }

    func didRead(on date: Date) -> Bool {
        readingDays.contains(Self.dayFormatter.string(from: date))
    }

    /// The longest run of days in a row with any reading.
    var longestStreak: Int {
        let calendar = Calendar.current
        let days = readingDays
            .compactMap { Self.dayFormatter.date(from: $0) }
            .map { calendar.startOfDay(for: $0) }
            .sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    // MARK: Pins and grouping

    func togglePin(_ id: UUID) {
        update(id) { book in
            book.pinned = (book.pinned ?? false) ? nil : true
        }
    }

    /// Every series in the box, with how many comics it holds.
    var seriesList: [(key: String, name: String, count: Int)] {
        var names: [String: String] = [:]
        var counts: [String: Int] = [:]
        for book in books {
            guard let key = book.seriesKey else { continue }
            if names[key] == nil { names[key] = book.series ?? key }
            counts[key, default: 0] += 1
        }
        return names
            .map { (key: $0.key, name: $0.value, count: counts[$0.key] ?? 0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Puts a comic into the named series, working out its issue number if it has none.
    func group(_ id: UUID, withSeries name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(id) { book in
            book.series = trimmed
            if book.number == nil {
                book.number = TitleParser.seriesAndNumber(in: book.title)?.number
            }
        }
    }

    /// Groups two comics together, starting a series from the other comic if it has none.
    func group(_ id: UUID, withBook otherID: UUID) {
        guard let other = book(otherID) else { return }
        let name = other.seriesKey != nil
            ? (other.series ?? other.title)
            : (TitleParser.seriesAndNumber(in: other.title)?.series ?? other.title)
        group(otherID, withSeries: name)
        group(id, withSeries: name)
    }

    func ungroup(_ id: UUID) {
        update(id) { book in
            book.series = nil
            book.number = nil
        }
    }

    // MARK: Folders

    var sortedFolders: [ComicFolder] {
        folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func folder(_ id: UUID) -> ComicFolder? {
        folders.first { $0.id == id }
    }

    func books(in folderID: UUID) -> [Book] {
        books
            .filter { ($0.folderIDs ?? []).contains(folderID) }
            .sorted { a, b in
                let left = a.seriesKey ?? a.title.lowercased()
                let right = b.seriesKey ?? b.title.lowercased()
                if left != right { return left.localizedStandardCompare(right) == .orderedAscending }
                let leftNumber = a.number ?? Double.greatestFiniteMagnitude
                let rightNumber = b.number ?? Double.greatestFiniteMagnitude
                if leftNumber != rightNumber { return leftNumber < rightNumber }
                return a.title.localizedStandardCompare(b.title) == .orderedAscending
            }
    }

    /// Makes a folder, or returns the one that already has this name.
    @discardableResult
    func createFolder(named name: String) -> ComicFolder? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = folders.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let folder = ComicFolder(id: UUID(), name: trimmed, createdAt: Date())
        folders.append(folder)
        saveFolders()
        return folder
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
        saveFolders()
    }

    /// Removes the folder. The comics in it stay in the box.
    func deleteFolder(_ id: UUID) {
        folders.removeAll { $0.id == id }
        saveFolders()
        var changed = false
        for index in books.indices {
            if var ids = books[index].folderIDs, ids.contains(id) {
                ids.removeAll { $0 == id }
                books[index].folderIDs = ids.isEmpty ? nil : ids
                changed = true
            }
        }
        if changed { save() }
    }

    /// True when every one of these comics is already in the folder.
    func allIn(_ bookIDs: [UUID], folder folderID: UUID) -> Bool {
        let wanted = Set(bookIDs)
        let members = books.filter { wanted.contains($0.id) }
        return !members.isEmpty && members.allSatisfy { ($0.folderIDs ?? []).contains(folderID) }
    }

    func add(_ bookIDs: [UUID], to folderID: UUID) {
        let wanted = Set(bookIDs)
        for index in books.indices where wanted.contains(books[index].id) {
            var ids = books[index].folderIDs ?? []
            if !ids.contains(folderID) {
                ids.append(folderID)
                books[index].folderIDs = ids
            }
        }
        save()
    }

    func remove(_ bookIDs: [UUID], from folderID: UUID) {
        let wanted = Set(bookIDs)
        for index in books.indices where wanted.contains(books[index].id) {
            guard var ids = books[index].folderIDs else { continue }
            ids.removeAll { $0 == folderID }
            books[index].folderIDs = ids.isEmpty ? nil : ids
        }
        save()
    }

    /// Adds the comics to the folder, or takes them out if they're all in it already.
    func toggle(_ bookIDs: [UUID], in folderID: UUID) {
        if allIn(bookIDs, folder: folderID) {
            remove(bookIDs, from: folderID)
        } else {
            add(bookIDs, to: folderID)
        }
    }

    private func saveFolders() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        let file = Storage.foldersFile
        saveQueue.async {
            try? data.write(to: file, options: .atomic)
        }
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
        enqueue(urls.map { ($0, false, nil) })
    }

    /// Picks up comics dropped into the Longbox folder (Files app, or USB from a computer).
    /// Files inside a subfolder also go into an app folder with that subfolder's name.
    func scanDropFolder() {
        let fm = FileManager.default
        let root = Storage.dropFolder
        Storage.prepareDropFolder()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]

        func comics(in directory: URL) -> [URL] {
            guard let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { return [] }
            var found: [URL] = []
            for url in items {
                guard ["cbz", "cbr", "zip", "rar"].contains(url.pathExtension.lowercased()) else { continue }
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                // A file still being copied over keeps changing; leave it for the next pass.
                if let modified = values?.contentModificationDate, Date().timeIntervalSince(modified) < 3 {
                    continue
                }
                found.append(url)
            }
            return found.sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }

        var queue: [(URL, Bool, String?)] = []
        for url in comics(in: root) + comics(in: root.appendingPathComponent("Inbox", isDirectory: true)) {
            queue.append((url, true, nil))
        }

        let subfolders = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        for directory in subfolders {
            let values = try? directory.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { continue }
            let name = directory.lastPathComponent
            if name == "Inbox" || name == "Not imported" { continue }
            let inside = comics(in: directory)
            if inside.isEmpty {
                // Tidy up subfolders that have been fully imported.
                if let rest = try? fm.contentsOfDirectory(atPath: directory.path), rest.isEmpty {
                    try? fm.removeItem(at: directory)
                }
                continue
            }
            for url in inside {
                queue.append((url, true, name))
            }
        }
        enqueue(queue)
    }

    private func enqueue(_ items: [(URL, Bool, String?)]) {
        for item in items {
            let path = Storage.canonicalPath(item.0)
            if path == currentImportPath { continue }
            if pending.contains(where: { Storage.canonicalPath($0.url) == path }) { continue }
            pending.append((item.0, item.1, item.2))
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
                    var book = try await Task.detached(priority: .userInitiated) {
                        try Importer.importBook(from: url)
                    }.value
                    if let name = item.folderName, let folder = createFolder(named: name) {
                        book.folderIDs = [folder.id]
                    }
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
        let today = Self.dayFormatter.string(from: Date())
        dailySeconds[today, default: 0] += seconds
        UserDefaults.standard.set(dailySeconds, forKey: "dailySeconds")
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
