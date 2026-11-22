import Foundation

/// Data introduced by recent Xcode releases.
struct ExtrasScanner: CleanupScanner {
    let category = CategoryID.extras

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        var items = Self.agentItems(paths: context.paths, xcodeBuild: context.xcodeBuild)
        if FS.isDirectory(context.paths.products), !FS.children(of: context.paths.products).isEmpty {
            items.append(CleanableItem(
                id: "extras:products", category: .extras,
                title: "Organizer data",
                detail: "Crash reports and metrics Xcode downloaded for your apps. Managed by Xcode; not removed here.",
                path: context.paths.products, size: nil,
                lastUsed: FS.modificationDate(context.paths.products),
                risk: .caution, action: .none, badge: "Info", flags: [.infoOnly]
            ))
        }
        return items
    }

    /// Xcode keeps every coding-agent version it ever downloaded. Only the one the selected Xcode links to is needed.
    static func agentItems(paths: Paths, xcodeBuild: String?) -> [CleanableItem] {
        let versions = FS.children(of: paths.codingAgents).filter { FS.isDirectory($0) && !FS.isSymlink($0) }
        guard versions.count > 1 else { return [] }

        // XcodeVersions/<build>/claude is a symlink to the agent version that build uses.
        var usedBy: [String: [String]] = [:]   // version folder name → Xcode builds
        for buildFolder in FS.children(of: paths.codingAgentXcodeVersions) {
            let link = buildFolder.appending(path: "claude")
            guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { continue }
            usedBy[URL(fileURLWithPath: target).lastPathComponent, default: []].append(buildFolder.lastPathComponent)
        }

        let newest = versions.map(\.lastPathComponent).max { $0.compare($1, options: .numeric) == .orderedAscending }
        let current = xcodeBuild.flatMap { build in usedBy.first { $0.value.contains(build) }?.key }
        // Without a known current build, be conservative and keep everything any Xcode links to.
        let keep: Set<String> = current.map { [$0] } ?? Set(usedBy.keys).union(newest.map { [$0] } ?? [])

        return versions.map { folder in
            let version = folder.lastPathComponent
            let inUse = keep.contains(version) || version == newest
            let builds = usedBy[version] ?? []
            // Remove the now-dangling XcodeVersions entries of other Xcode builds along with the agent.
            let staleLinks = builds
                .filter { $0 != xcodeBuild }
                .map { paths.codingAgentXcodeVersions.appending(path: $0) }
                .filter { FS.isDirectory($0) && !FS.isSymlink($0) }

            let detail: String = if inUse {
                "Used by the selected Xcode"
            } else if builds.isEmpty {
                "Not linked to any Xcode build"
            } else {
                "Was used by Xcode build \(builds.joined(separator: ", "))"
            }

            return CleanableItem(
                id: "agent:" + folder.path, category: .extras,
                title: "Coding agent \(version)", detail: detail,
                path: folder, size: nil,
                lastUsed: FS.modificationDate(folder),
                risk: .caution,
                action: inUse ? .none : .files([folder] + staleLinks),
                badge: inUse ? "In use" : "Old version",
                flags: inUse ? [.infoOnly] : [.superseded],
                group: "coding-agent", version: version
            )
        }
    }
}
