import Foundation
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published var importingName: String?
    @Published var errorMessage: String?

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
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: Storage.libraryFile, options: .atomic)
    }
}
