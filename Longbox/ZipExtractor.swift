import Foundation
import ZIPFoundation

/// Unpacks the image pages of a .cbz (zip) archive into a folder.
enum ZipExtractor {
    static func extract(archive url: URL, to folder: URL) throws -> [String] {
        let archive = try Archive(url: url, accessMode: .read)

        var entries: [Entry] = []
        for entry in archive {
            if entry.type == .file && PageNaming.isPage(entry.path) {
                entries.append(entry)
            }
        }
        entries.sort { PageNaming.precedes($0.path, $1.path) }

        var names: [String] = []
        for (index, entry) in entries.enumerated() {
            let name = PageNaming.fileName(index: index, originalPath: entry.path)
            _ = try archive.extract(entry, to: folder.appendingPathComponent(name))
            names.append(name)
        }
        return names
    }
}
