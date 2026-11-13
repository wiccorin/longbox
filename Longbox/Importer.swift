import Foundation
import UIKit

enum ImportError: LocalizedError {
    case unsupported
    case noPages
    case encrypted
    case unreadable

    var errorDescription: String? {
        switch self {
        case .unsupported: return "This isn't a .cbz or .cbr file."
        case .noPages: return "No images were found inside this file."
        case .encrypted: return "This file is password protected."
        case .unreadable: return "The file couldn't be read."
        }
    }
}

/// Turns a picked .cbz/.cbr file into a book stored in the app.
enum Importer {
    private enum Format { case zip, rar }

    static func importBook(from source: URL) throws -> Book {
        let fm = FileManager.default
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        // Work on a private copy so the original can go away mid-import.
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try fm.copyItem(at: source, to: temp)
        } catch {
            throw ImportError.unreadable
        }
        defer { try? fm.removeItem(at: temp) }

        // Go by the file's contents, since many .cbr files are really zips.
        guard let format = detectFormat(temp) else { throw ImportError.unsupported }

        let id = UUID()
        let folder = Storage.folder(for: id)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            let extracted: ExtractedArchive
            switch format {
            case .zip: extracted = try ZipExtractor.extract(archive: temp, to: folder)
            case .rar: extracted = try RarExtractor.extract(archive: temp, to: folder)
            }
            let pages = extracted.pages
            guard !pages.isEmpty else { throw ImportError.noPages }

            let first = folder.appendingPathComponent(pages[0])
            if let cover = PageImage.downsampled(first, shortSide: 420),
               let jpeg = cover.jpegData(compressionQuality: 0.82) {
                try? jpeg.write(to: Storage.cover(for: id))
            }

            let rawName = source.deletingPathExtension().lastPathComponent
            var book = Book(
                id: id,
                title: TitleParser.clean(rawName),
                pages: pages,
                currentPage: 0,
                mode: .leftToRight,
                addedAt: Date(),
                lastReadAt: nil
            )
            book.year = TitleParser.year(in: rawName)

            var chapters = TitleParser.chapters(fromFolders: extracted.folders)
            if let data = extracted.comicInfo, let info = ComicInfoParser.parse(data) {
                book.series = info.series
                book.writer = info.writer
                book.publisher = info.publisher
                book.summary = info.summary
                if let year = info.year { book.year = year }
                book.month = info.month
                if info.manga == "YesAndRightToLeft" { book.mode = .rightToLeft }
                let marks = info.bookmarks.filter { pages.indices.contains($0.startPage) }
                if !marks.isEmpty { chapters = marks }
            }
            book.chapters = chapters.isEmpty ? nil : chapters
            return book
        } catch {
            try? fm.removeItem(at: folder)
            throw error
        }
    }

    private static func detectFormat(_ url: URL) -> Format? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let head = [UInt8](handle.readData(ofLength: 4))
        guard head.count == 4 else { return nil }
        if head[0] == 0x50 && head[1] == 0x4B { return .zip }
        if head[0] == 0x52 && head[1] == 0x61 && head[2] == 0x72 && head[3] == 0x21 { return .rar }
        return nil
    }
}
