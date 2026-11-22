import Foundation

/// The single gate every file deletion passes through.
///
/// A path may be removed only when all of these hold:
/// - it exists and is not itself a symbolic link,
/// - its real location (symlinks in parent folders resolved) is strictly inside an allowed root,
///   or it is a recognised build folder inside a project folder the user chose,
/// - it is not a protected path, does not contain one, and is not inside one,
/// - it is on the same volume as its parent folder, so mount points are never touched.
struct SafetyGuard: Sendable {
    var roots: [URL]
    var protected: [URL]
    var projectRoots: [URL]

    init(paths: Paths, projectRoots: [URL] = []) {
        self.roots = paths.deletableRoots
        self.protected = paths.protectedPaths
        self.projectRoots = projectRoots
    }

    init(roots: [URL], protected: [URL] = [], projectRoots: [URL] = []) {
        self.roots = roots
        self.protected = protected
        self.projectRoots = projectRoots
    }

    enum Violation: Error, LocalizedError, Equatable {
        case missing(String)
        case symlink(String)
        case outsideAllowedRoots(String)
        case isRootItself(String)
        case protected(String)
        case mountPoint(String)
        case notABuildFolder(String)

        var errorDescription: String? {
            switch self {
            case .missing(let p): "Nothing exists at \(p)."
            case .symlink(let p): "\(p) is a symbolic link and was left alone."
            case .outsideAllowedRoots(let p): "\(p) is outside the folders XcodePimp is allowed to clean."
            case .isRootItself(let p): "\(p) is a top-level Xcode folder and is never removed."
            case .protected(let p): "\(p) is protected and is never removed."
            case .mountPoint(let p): "\(p) is a mounted volume and was left alone."
            case .notABuildFolder(let p): "\(p) is not a recognised build folder next to a project."
            }
        }
    }

    /// Returns the resolved URL that is safe to delete, or throws.
    @discardableResult
    func validate(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        var info = stat()
        guard lstat(path, &info) == 0 else { throw Violation.missing(path) }
        guard (info.st_mode & S_IFMT) != S_IFLNK else { throw Violation.symlink(path) }

        // Resolve symlinks in the parent chain only; the item itself is known not to be a link.
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolved = parent.appending(path: standardized.lastPathComponent)
        let components = Self.components(resolved)

        for item in protected {
            let other = Self.components(item.resolvingSymlinksInPath())
            if Self.isPrefix(other, of: components) || Self.isPrefix(components, of: other) {
                throw Violation.protected(path)
            }
        }

        var parentInfo = stat()
        if lstat(parent.path, &parentInfo) == 0, parentInfo.st_dev != info.st_dev {
            throw Violation.mountPoint(path)
        }

        for root in roots {
            let rootComponents = Self.components(root.resolvingSymlinksInPath())
            if rootComponents == components { throw Violation.isRootItself(path) }
            if Self.isPrefix(rootComponents, of: components) { return resolved }
        }

        for root in projectRoots {
            let rootComponents = Self.components(root.resolvingSymlinksInPath())
            guard Self.isPrefix(rootComponents, of: components), rootComponents != components else { continue }
            guard ProjectArtifact.kind(of: resolved) != nil else { throw Violation.notABuildFolder(path) }
            return resolved
        }

        throw Violation.outsideAllowedRoots(path)
    }

    private static func components(_ url: URL) -> [String] {
        url.standardizedFileURL.pathComponents
    }

    private static func isPrefix(_ prefix: [String], of full: [String]) -> Bool {
        prefix.count <= full.count && Array(full.prefix(prefix.count)) == prefix
    }
}

/// Recognises regenerable build folders inside a project folder.
enum ProjectArtifact: String, Sendable {
    case swiftBuild = ".build"
    case xcodeBuild = "build"
    case derivedData = "DerivedData"
    case pods = "Pods"
    case carthageBuild = "Carthage/Build"

    var risk: Risk {
        switch self {
        case .swiftBuild, .xcodeBuild, .derivedData: .safe
        case .pods, .carthageBuild: .caution
        }
    }

    var explanation: String {
        switch self {
        case .swiftBuild: "Swift package build folder"
        case .xcodeBuild: "Xcode build folder"
        case .derivedData: "Project-local derived data"
        case .pods: "Installed pods — run pod install to restore"
        case .carthageBuild: "Carthage build output — run carthage bootstrap to restore"
        }
    }

    /// Returns the artifact kind only when the folder sits next to the project file that produces it.
    static func kind(of url: URL) -> ProjectArtifact? {
        guard FS.isDirectory(url), !FS.isSymlink(url) else { return nil }
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent()

        func sibling(_ name: String) -> Bool { FS.exists(parent.appending(path: name)) }
        func siblingWithExtension(_ exts: Set<String>) -> Bool {
            FS.children(of: parent).contains { exts.contains($0.pathExtension) }
        }
        let hasXcodeProject = { siblingWithExtension(["xcodeproj", "xcworkspace"]) }

        switch name {
        case ".build":
            return sibling("Package.swift") ? .swiftBuild : nil
        case "DerivedData":
            return hasXcodeProject() || sibling("Package.swift") ? .derivedData : nil
        case "build":
            guard hasXcodeProject() else { return nil }
            // A folder called "build" could be anything; require Xcode's own layout inside it.
            let looksLikeXcodeOutput = FS.children(of: url).contains { child in
                let n = child.lastPathComponent
                return n == "XCBuildData" || n.hasSuffix(".build") || n.hasPrefix("Debug") || n.hasPrefix("Release")
            }
            return looksLikeXcodeOutput ? .xcodeBuild : nil
        case "Pods":
            return sibling("Podfile") ? .pods : nil
        case "Build":
            guard parent.lastPathComponent == "Carthage" else { return nil }
            let projectDir = parent.deletingLastPathComponent()
            return FS.exists(projectDir.appending(path: "Cartfile")) ? .carthageBuild : nil
        default:
            return nil
        }
    }
}
