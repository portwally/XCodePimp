import Foundation

struct DeviceSupportScanner: CleanupScanner {
    let category = CategoryID.deviceSupport

    struct Parsed: Equatable, Sendable {
        let model: String?
        let version: String
        let build: String
    }

    /// "iPhone11,2 18.7.10 (22H374)", "16.4 (20E247)", "16.4 (20E247) arm64e"
    static func parse(_ name: String) -> Parsed? {
        let pattern = /^(?:(\S+) )?(\d[\d.]*) \((\w+)\)(?: \S+)?$/
        guard let match = name.wholeMatch(of: pattern) else { return nil }
        return Parsed(model: match.1.map(String.init), version: String(match.2), build: String(match.3))
    }

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        context.paths.deviceSupportRoots.flatMap { Self.items(platform: $0.platform, root: $0.url) }
    }

    static func items(platform: String, root: URL) -> [CleanableItem] {
        let folders = FS.children(of: root).filter { FS.isDirectory($0) && !FS.isSymlink($0) }
        let parsed = folders.map { ($0, parse($0.lastPathComponent)) }

        // Newest OS version per device model is the one worth keeping.
        var newest: [String: (version: String, build: String)] = [:]
        for (_, info) in parsed {
            guard let info else { continue }
            let key = "\(platform)|\(info.model ?? "")"
            if let current = newest[key], !isNewer(info, than: current) { continue }
            newest[key] = (info.version, info.build)
        }

        return parsed.map { folder, info in
            let key = "\(platform)|\(info?.model ?? "")"
            let isLatest = info.map { newest[key]?.build == $0.build } ?? true
            let title = info.map { "\(platform) \($0.version) (\($0.build))" } ?? folder.lastPathComponent
            return CleanableItem(
                id: "ds:" + folder.path, category: .deviceSupport,
                title: title, detail: info?.model ?? "\(platform) device",
                path: folder, size: nil,
                lastUsed: FS.modificationDate(folder),
                risk: isLatest ? .caution : .safe,
                action: .files([folder]),
                badge: isLatest ? "Latest" : "Superseded",
                flags: isLatest ? [] : [.superseded],
                group: key, version: info?.version
            )
        }
    }

    private static func isNewer(_ info: Parsed, than current: (version: String, build: String)) -> Bool {
        let order = info.version.compare(current.version, options: .numeric)
        if order != .orderedSame { return order == .orderedDescending }
        return info.build.compare(current.build, options: .numeric) == .orderedDescending
    }
}
