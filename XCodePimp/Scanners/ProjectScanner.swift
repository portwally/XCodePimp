import Foundation

/// Finds regenerable build folders inside the folders the user picked.
struct ProjectScanner: CleanupScanner {
    let category = CategoryID.projects

    static let maxDepth = 6
    private static let skippedNames: Set<String> = ["node_modules", "Library", "Applications", "System"]
    private static let bundleExtensions: Set<String> = [
        "app", "xcodeproj", "xcworkspace", "xcarchive", "framework", "xcframework",
        "bundle", "playground", "photoslibrary", "xcassets", "lproj",
    ]

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        let roots = context.projectRoots
        guard !roots.isEmpty else { return [] }

        let candidates = await Task.detached(priority: .utility) {
            var found: [(URL, ProjectArtifact)] = []
            for root in roots { Self.walk(root, depth: 0, into: &found) }
            return found
        }.value

        var items: [CleanableItem] = []
        for (url, kind) in candidates {
            // Anything committed to git is someone's deliberate choice, not a disposable build product.
            if await Self.isTrackedByGit(url) { continue }
            let project = kind == .carthageBuild
                ? url.deletingLastPathComponent().deletingLastPathComponent()
                : url.deletingLastPathComponent()
            items.append(CleanableItem(
                id: "proj:" + url.path, category: .projects,
                title: "\(project.lastPathComponent) — \(kind.rawValue)",
                detail: kind.explanation + " · " + project.path,
                path: url, size: nil,
                lastUsed: FS.modificationDate(url),
                risk: kind.risk, action: .files([url]),
                group: project.path
            ))
        }
        return items
    }

    static func walk(_ directory: URL, depth: Int, into found: inout [(URL, ProjectArtifact)]) {
        guard depth <= maxDepth else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []
        )) ?? []

        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let name = entry.lastPathComponent

            if let kind = ProjectArtifact.kind(of: entry) {
                found.append((entry, kind))
                continue   // never look inside a build folder
            }
            if name == "Carthage" {
                let build = entry.appending(path: "Build")
                if let kind = ProjectArtifact.kind(of: build) { found.append((build, kind)) }
                continue
            }
            if name.hasPrefix(".") || skippedNames.contains(name) || bundleExtensions.contains(entry.pathExtension) {
                continue
            }
            walk(entry, depth: depth + 1, into: &found)
        }
    }

    static func isTrackedByGit(_ url: URL) async -> Bool {
        let parent = url.deletingLastPathComponent().path
        guard let output = try? await ProcessRunner.run(
            "/usr/bin/git", ["-C", parent, "ls-files", "--", url.lastPathComponent]
        ), output.succeeded else { return false }
        return !output.stdout.isEmpty
    }
}
