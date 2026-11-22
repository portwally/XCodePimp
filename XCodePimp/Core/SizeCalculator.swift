import Foundation

enum SizeCalculator {
    private static let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]

    /// Bytes actually allocated on disk for a file or a whole folder tree. Symbolic links are not followed.
    static func allocatedSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        guard values.isDirectory == true else {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let v = try? file.resourceValues(forKeys: keys) else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func allocatedSize(of urls: [URL]) -> Int64 {
        urls.reduce(0) { $0 + allocatedSize(of: $1) }
    }

    /// Off the caller's executor; folder walks can take seconds.
    static func measure(_ urls: [URL]) async -> Int64 {
        await Task.detached(priority: .utility) { allocatedSize(of: urls) }.value
    }
}
