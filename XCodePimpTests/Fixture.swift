import Foundation
@testable import XCodePimp

/// A throwaway home folder under the temp directory.
final class Fixture {
    let home: URL
    let paths: Paths

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appending(path: "XCodePimpTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        home = base.resolvingSymlinksInPath()
        paths = Paths(home: home, systemDeveloper: home.appending(path: "SystemDeveloper"))
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    func makeDir(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func makeFile(_ url: URL, bytes: Int = 16) throws -> URL {
        try makeDir(url.deletingLastPathComponent())
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func writePlist(_ dictionary: [String: Any], to url: URL) throws {
        try makeDir(url.deletingLastPathComponent())
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        try data.write(to: url)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
