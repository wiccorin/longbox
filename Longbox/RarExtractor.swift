import Foundation
import Unrar

/// Unpacks the image pages of a .cbr (rar) archive into a folder.
enum RarExtractor {
    static func extract(archive url: URL, to folder: URL) throws -> [String] {
        let archive = try Archive(fileURL: url)

        let entries = try archive.entries()
            .filter { !$0.directory && PageNaming.isPage($0.fileName) }
            .sorted { PageNaming.precedes($0.fileName, $1.fileName) }

        var names: [String] = []
        for (index, entry) in entries.enumerated() {
            if entry.encrypted { throw ImportError.encrypted }
            let name = PageNaming.fileName(index: index, originalPath: entry.fileName)
            let data = try archive.extract(entry)
            try data.write(to: folder.appendingPathComponent(name))
            names.append(name)
        }
        return names
    }
}
