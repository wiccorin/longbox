import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var importingName: String?
    @Published var errorMessage: String?

    private let saveQueue = DispatchQueue(label: "longbox.library.save", qos: .utility)

    init() {
        Storage.prepare()
        load()
    }

    func book(_ id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    // MARK: Import

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task {
            var failures: [String] = []
            for url in urls {
                importingName = url.deletingPathExtension().lastPathComponent
                do {
                    let book = try await Task.detached(priority: .userInitiated) {
                        try Importer.importBook(from: url)
                    }.value
                    books.append(book)
                    save()
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            importingName = nil
            if !failures.isEmpty {
                errorMessage = failures.joined(separator: "\n")
            }
        }
    }

    // MARK: Changes

    func setPage(_ page: Int, for id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        let clamped = min(max(page, 0), max(books[index].pageCount - 1, 0))
        books[index].currentPage = clamped
        books[index].lastReadAt = Date()
        save()
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

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].title = trimmed
        save()
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

        // Libraries from earlier builds have no release year; recover it from the title.
        var changed = false
        for index in books.indices where books[index].year == nil {
            if let year = TitleParser.year(in: books[index].title) {
                books[index].year = year
                changed = true
            }
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
