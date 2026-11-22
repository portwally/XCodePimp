import Foundation

struct CacheScanner: CleanupScanner {
    let category = CategoryID.caches

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        Self.folderItems(context.paths.cacheFolders) + Self.dyldItems(root: context.paths.systemDyldCaches)
    }

    /// One item per cache folder. Cleaning empties the folder but keeps the folder itself.
    static func folderItems(_ folders: [Paths.CacheFolder]) -> [CleanableItem] {
        folders.compactMap { folder in
            guard FS.isDirectory(folder.url), !FS.isSymlink(folder.url) else { return nil }
            let contents = FS.children(of: folder.url).filter { !FS.isSymlink($0) }
            guard !contents.isEmpty else { return nil }
            return CleanableItem(
                id: "cache:" + folder.url.path, category: .caches,
                title: folder.title, detail: folder.detail,
                path: folder.url, size: nil,
                lastUsed: FS.modificationDate(folder.url),
                risk: .safe, action: .files(contents),
                flags: folder.isLog ? [.log] : []
            )
        }
    }

    /// Simulator dyld caches are owned by root and disappear together with their runtime.
    static func dyldItems(root: URL) -> [CleanableItem] {
        FS.children(of: root)
            .flatMap { FS.children(of: $0) }
            .filter { FS.isDirectory($0) && $0.lastPathComponent.contains("SimRuntime") }
            .map { folder in
                let name = folder.lastPathComponent
                let runtime = name.split(separator: ".").dropLast().joined(separator: ".")
                return CleanableItem(
                    id: "dyld:" + folder.path, category: .caches,
                    title: "Simulator dyld cache — \(Simctl.displayName(runtimeIdentifier: runtime))",
                    detail: "System-owned. Removed automatically when you delete this runtime.",
                    path: folder, size: nil,
                    lastUsed: FS.modificationDate(folder),
                    risk: .caution, action: .none,
                    badge: "Info", flags: [.infoOnly]
                )
            }
    }
}
