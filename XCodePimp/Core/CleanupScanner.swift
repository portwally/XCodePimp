import Foundation

struct ScanContext: Sendable {
    var paths: Paths = .live
    var projectRoots: [URL] = []
    /// Build number of the selected Xcode, e.g. "27B48".
    var xcodeBuild: String?

    static func currentXcodeBuild() async -> String? {
        var candidates: [URL] = []
        if let output = try? await ProcessRunner.run("/usr/bin/xcode-select", ["-p"]), output.succeeded {
            let developerDir = URL(fileURLWithPath: output.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
            candidates.append(developerDir.deletingLastPathComponent().appending(path: "version.plist"))
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/version.plist"))
        for url in candidates {
            if let build = FS.plist(at: url)?["ProductBuildVersion"] as? String { return build }
        }
        return nil
    }
}

/// Finds the cleanable items of one category. Scanners never delete anything.
protocol CleanupScanner: Sendable {
    var category: CategoryID { get }
    func scan(_ context: ScanContext) async -> [CleanableItem]
}

enum Scanners {
    static let all: [any CleanupScanner] = [
        DerivedDataScanner(),
        RuntimeScanner(),
        DeviceScanner(),
        DeviceSupportScanner(),
        ArchiveScanner(),
        CacheScanner(),
        ExtrasScanner(),
        ProjectScanner(),
    ]
}
