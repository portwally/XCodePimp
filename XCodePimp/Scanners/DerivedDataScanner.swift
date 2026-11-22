import Foundation

struct DerivedDataScanner: CleanupScanner {
    let category = CategoryID.derivedData

    /// Caches shared by every project.
    static let sharedCaches: [String: String] = [
        "ModuleCache.noindex": "Precompiled Clang and Swift modules",
        "CompilationCache.noindex": "Compilation cache shared between builds",
        "SymbolCache.noindex": "Symbol cache used by the debugger and Instruments",
        "SDKStatCaches.noindex": "File-system stat caches for the SDKs",
        "SDKExplicitPrecompiledModules": "Explicitly built SDK modules",
    ]

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        Self.items(in: context.paths.derivedData)
    }

    static func items(in root: URL) -> [CleanableItem] {
        var items = scanFolders(in: root)

        // A project often has several folders here: one per location it was ever opened from
        // (a git worktree, a duplicate, a moved folder). Say so when the live project still exists,
        // otherwise "project gone" reads as if the real project were missing.
        let liveNames = Set(items.filter { !$0.flags.contains(.orphaned) && !$0.flags.contains(.sharedCache) }.map(\.title))
        for index in items.indices where items[index].flags.contains(.orphaned) && liveNames.contains(items[index].title) {
            items[index].badge = "Deleted copy"
            items[index].flags.insert(.duplicate)
        }
        return items
    }

    private static func scanFolders(in root: URL) -> [CleanableItem] {
        FS.children(of: root).compactMap { folder -> CleanableItem? in
            guard FS.isDirectory(folder), !FS.isSymlink(folder) else { return nil }
            let name = folder.lastPathComponent

            if let explanation = sharedCaches[name] ?? (name.hasSuffix(".noindex") ? "Shared build cache" : nil) {
                return CleanableItem(
                    id: "dd:" + folder.path, category: .derivedData,
                    title: name, detail: explanation, path: folder, size: nil,
                    lastUsed: FS.modificationDate(folder), risk: .safe,
                    action: .files([folder]), badge: "Shared", flags: [.sharedCache]
                )
            }

            let info = FS.plist(at: folder.appending(path: "info.plist"))
            let workspace = info?["WorkspacePath"] as? String
            let accessed = info?["LastAccessedDate"] as? Date
            let orphaned = workspace.map { !FS.exists(URL(fileURLWithPath: $0)) } ?? false

            return CleanableItem(
                id: "dd:" + folder.path, category: .derivedData,
                title: projectName(folder: name, workspace: workspace),
                detail: workspace ?? name,
                path: folder, size: nil,
                lastUsed: accessed ?? FS.modificationDate(folder),
                risk: .safe, action: .files([folder]),
                badge: orphaned ? "Project gone" : nil,
                flags: orphaned ? [.orphaned] : []
            )
        }
    }

    /// "Alerta-ddovwvcdrqvnwmflolceukbairdh" → "Alerta"
    static func projectName(folder: String, workspace: String?) -> String {
        if let workspace {
            return URL(fileURLWithPath: workspace).deletingPathExtension().lastPathComponent
        }
        if let dash = folder.lastIndex(of: "-"), folder.distance(from: dash, to: folder.endIndex) == 29 {
            return String(folder[..<dash])
        }
        return folder
    }
}
