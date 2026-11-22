import Foundation

struct ArchiveScanner: CleanupScanner {
    let category = CategoryID.archives

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        Self.items(in: context.paths.archives)
    }

    static func items(in root: URL) -> [CleanableItem] {
        // Xcode files archives as Archives/<date>/<name>.xcarchive.
        var archives: [URL] = []
        for child in FS.children(of: root) where FS.isDirectory(child) && !FS.isSymlink(child) {
            if child.pathExtension == "xcarchive" {
                archives.append(child)
            } else {
                archives += FS.children(of: child).filter { $0.pathExtension == "xcarchive" && !FS.isSymlink($0) }
            }
        }

        return archives.map { archive in
            let info = FS.plist(at: archive.appending(path: "Info.plist"))
            let app = info?["ApplicationProperties"] as? [String: Any]
            let name = (info?["Name"] as? String) ?? archive.deletingPathExtension().lastPathComponent
            let short = app?["CFBundleShortVersionString"] as? String
            let build = app?["CFBundleVersion"] as? String
            let bundleID = app?["CFBundleIdentifier"] as? String
            let uploaded = !((info?["Distributions"] as? [Any]) ?? []).isEmpty

            var title = name
            if let short { title += " \(short)" }
            if let build { title += " (\(build))" }

            return CleanableItem(
                id: "ar:" + archive.path, category: .archives,
                title: title, detail: bundleID ?? archive.lastPathComponent,
                path: archive, size: nil,
                lastUsed: (info?["CreationDate"] as? Date) ?? FS.modificationDate(archive),
                risk: .keep, action: .files([archive]),
                badge: uploaded ? "Distributed" : nil,
                group: bundleID ?? name, version: build
            )
        }
    }
}
