import Foundation

/// Every location the app knows about, derived from a home folder so tests can point it at a fixture.
struct Paths: Sendable {
    let home: URL
    let systemDeveloper: URL

    static let live = Paths(
        home: FileManager.default.homeDirectoryForCurrentUser,
        systemDeveloper: URL(fileURLWithPath: "/Library/Developer", isDirectory: true)
    )

    private func dir(_ relative: String) -> URL {
        home.appending(path: relative, directoryHint: .isDirectory)
    }

    var developer: URL { dir("Library/Developer") }
    var xcode: URL { dir("Library/Developer/Xcode") }
    var derivedData: URL { dir("Library/Developer/Xcode/DerivedData") }
    var archives: URL { dir("Library/Developer/Xcode/Archives") }
    var userData: URL { dir("Library/Developer/Xcode/UserData") }
    var products: URL { dir("Library/Developer/Xcode/Products") }
    var codingAssistant: URL { dir("Library/Developer/Xcode/CodingAssistant") }
    var codingAgents: URL { dir("Library/Developer/Xcode/CodingAssistant/Agents/claude") }
    var codingAgentXcodeVersions: URL { dir("Library/Developer/Xcode/CodingAssistant/Agents/XcodeVersions") }
    var simulatorDevices: URL { dir("Library/Developer/CoreSimulator/Devices") }
    var simulatorLogs: URL { dir("Library/Logs/CoreSimulator") }
    var systemDyldCaches: URL { systemDeveloper.appending(path: "CoreSimulator/Caches/dyld", directoryHint: .isDirectory) }

    static let deviceSupportPlatforms = ["iOS", "watchOS", "tvOS", "visionOS", "xrOS", "macOS"]

    var deviceSupportRoots: [(platform: String, url: URL)] {
        Self.deviceSupportPlatforms.map { ($0, dir("Library/Developer/Xcode/\($0) DeviceSupport")) }
    }

    struct CacheFolder: Sendable {
        let title: String
        let detail: String
        let url: URL
        let isLog: Bool
    }

    /// Folders whose *contents* are disposable. The folder itself is always kept.
    var cacheFolders: [CacheFolder] {
        [
            CacheFolder(title: "Documentation cache", detail: "Downloaded developer documentation", url: dir("Library/Developer/Xcode/DocumentationCache"), isLog: false),
            CacheFolder(title: "Documentation index", detail: "Search index for documentation", url: dir("Library/Developer/Xcode/DocumentationIndex"), isLog: false),
            CacheFolder(title: "Device logs", detail: "Crash and diagnostic logs pulled from connected devices", url: dir("Library/Developer/Xcode/DeviceLogs"), isLog: true),
            CacheFolder(title: "Simulator logs", detail: "Logs written by simulators", url: simulatorLogs, isLog: true),
            CacheFolder(title: "Swift Package Manager cache", detail: "Downloaded package repositories and artifacts", url: dir("Library/Caches/org.swift.swiftpm"), isLog: false),
            CacheFolder(title: "Xcode cache", detail: "com.apple.dt.Xcode", url: dir("Library/Caches/com.apple.dt.Xcode"), isLog: false),
            CacheFolder(title: "xcodebuild cache", detail: "com.apple.dt.xcodebuild", url: dir("Library/Caches/com.apple.dt.xcodebuild"), isLog: false),
            CacheFolder(title: "Xcode source control cache", detail: "com.apple.dt.Xcode.sourcecontrol.Git", url: dir("Library/Caches/com.apple.dt.Xcode.sourcecontrol.Git"), isLog: false),
            CacheFolder(title: "XCTest cache", detail: "com.apple.dt.xctest.tool", url: dir("Library/Caches/com.apple.dt.xctest.tool"), isLog: false),
            CacheFolder(title: "App Store Connect cache", detail: "com.apple.dt.Xcode.ITunesSoftwareService", url: dir("Library/Caches/com.apple.dt.Xcode.ITunesSoftwareService"), isLog: false),
            CacheFolder(title: "Instruments cache", detail: "com.apple.dt.Instruments", url: dir("Library/Caches/com.apple.dt.Instruments"), isLog: false),
            CacheFolder(title: "CocoaPods cache", detail: "Downloaded pods", url: dir("Library/Caches/CocoaPods"), isLog: false),
            CacheFolder(title: "Carthage cache", detail: "Downloaded Carthage dependencies", url: dir("Library/Caches/org.carthage.CarthageKit"), isLog: false),
        ]
    }

    /// The only folders file deletion may ever happen in. An item must be strictly inside one of them.
    var deletableRoots: [URL] {
        [derivedData, archives, codingAgents, codingAgentXcodeVersions]
            + deviceSupportRoots.map(\.url)
            + cacheFolders.map(\.url)
    }

    /// Never deleted, even if a rule above would otherwise match.
    var protectedPaths: [URL] {
        [
            userData,
            products,
            dir("Library/Developer/CoreDevice"),
            dir("Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig"),
            dir("Library/Developer/Xcode/CodingAssistant/mcp-servers.json"),
            dir("Library/MobileDevice"),
            dir("Library/Keychains"),
        ]
    }
}

/// Small file-system helpers shared by the scanners.
enum FS {
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }

    /// Direct children, without Finder's `.DS_Store`.
    static func children(of url: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        return urls
            .filter { $0.lastPathComponent != ".DS_Store" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func plist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
