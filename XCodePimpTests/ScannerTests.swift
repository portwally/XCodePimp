import Foundation
import Testing
@testable import XCodePimp

@Suite struct ScannerTests {
    let fx: Fixture

    init() throws { fx = try Fixture() }

    @Test func derivedDataFindsProjectsOrphansAndSharedCaches() throws {
        let dd = fx.paths.derivedData
        let project = try fx.makeDir(fx.home.appending(path: "Code/Alive/Alive.xcodeproj"))
        try fx.writePlist(["WorkspacePath": project.path, "LastAccessedDate": Date(timeIntervalSince1970: 1_000)],
                          to: dd.appending(path: "Alive-ddovwvcdrqvnwmflolceukbairdh/info.plist"))
        try fx.writePlist(["WorkspacePath": fx.home.appending(path: "Code/Gone/Gone.xcodeproj").path],
                          to: dd.appending(path: "Gone-hatekqnpchazhsfzlxlshupjegfh/info.plist"))
        try fx.makeDir(dd.appending(path: "ModuleCache.noindex"))
        try fx.makeFile(dd.appending(path: ".DS_Store"))

        let items = DerivedDataScanner.items(in: dd)
        #expect(items.count == 3)

        let alive = try #require(items.first { $0.title == "Alive" })
        #expect(alive.flags.isEmpty)
        #expect(alive.lastUsed == Date(timeIntervalSince1970: 1_000))
        #expect(alive.risk == .safe)

        let gone = try #require(items.first { $0.title == "Gone" })
        #expect(gone.flags.contains(.orphaned))

        let cache = try #require(items.first { $0.title == "ModuleCache.noindex" })
        #expect(cache.flags.contains(.sharedCache))

        // Every produced action must pass the guard.
        let guardian = SafetyGuard(paths: fx.paths)
        for item in items {
            guard case .files(let urls) = item.action else { Issue.record("expected files"); continue }
            for url in urls { #expect(throws: Never.self) { try guardian.validate(url) } }
        }
    }

    @Test func projectNameFallsBackToFolderName() {
        #expect(DerivedDataScanner.projectName(folder: "Alerta-ddovwvcdrqvnwmflolceukbairdh", workspace: nil) == "Alerta")
        #expect(DerivedDataScanner.projectName(folder: "My-App-ddovwvcdrqvnwmflolceukbairdh", workspace: nil) == "My-App")
        #expect(DerivedDataScanner.projectName(folder: "Odd", workspace: nil) == "Odd")
        #expect(DerivedDataScanner.projectName(folder: "x", workspace: "/a/b/Fluvio.xcworkspace") == "Fluvio")
    }

    @Test func deviceSupportNameParsing() {
        #expect(DeviceSupportScanner.parse("iPhone11,2 18.7.10 (22H374)")
                == .init(model: "iPhone11,2", version: "18.7.10", build: "22H374"))
        #expect(DeviceSupportScanner.parse("16.4 (20E247)") == .init(model: nil, version: "16.4", build: "20E247"))
        #expect(DeviceSupportScanner.parse("16.4 (20E247) arm64e") == .init(model: nil, version: "16.4", build: "20E247"))
        #expect(DeviceSupportScanner.parse("Something else") == nil)
    }

    @Test func deviceSupportKeepsNewestPerModel() throws {
        let root = fx.paths.deviceSupportRoots[0].url
        for name in ["iPhone11,2 18.7.10 (22H374)", "iPhone11,2 18.7.9 (22H300)", "iPhone11,2 18.7.12 (22H390)", "iPad8,1 17.0 (21A100)"] {
            try fx.makeDir(root.appending(path: name))
        }
        let items = DeviceSupportScanner.items(platform: "iOS", root: root)
        #expect(items.count == 4)
        let superseded = Set(items.filter { $0.flags.contains(.superseded) }.compactMap(\.version))
        #expect(superseded == ["18.7.10", "18.7.9"])
        #expect(items.first { $0.version == "18.7.12" }?.risk == .caution)
        #expect(items.first { $0.version == "17.0" }?.risk == .caution)
    }

    @Test func archivesReadInfoPlist() throws {
        let archive = fx.paths.archives.appending(path: "2026-11-21/Fluvio 21-11-2026, 22.55.xcarchive")
        try fx.writePlist([
            "Name": "Fluvio",
            "CreationDate": Date(timeIntervalSince1970: 5_000),
            "ApplicationProperties": ["CFBundleIdentifier": "com.example.Fluvio", "CFBundleShortVersionString": "2.3", "CFBundleVersion": "107"],
        ], to: archive.appending(path: "Info.plist"))

        let items = ArchiveScanner.items(in: fx.paths.archives)
        #expect(items.count == 1)
        #expect(items[0].title == "Fluvio 2.3 (107)")
        #expect(items[0].risk == .keep)
        #expect(items[0].lastUsed == Date(timeIntervalSince1970: 5_000))
    }

    @Test func cacheItemsEmptyTheFolderButKeepIt() async throws {
        let cache = try #require(fx.paths.cacheFolders.first { $0.title == "Swift Package Manager cache" })
        try fx.makeFile(cache.url.appending(path: "repositories/a/file"), bytes: 4096)
        try fx.makeFile(cache.url.appending(path: "manifests.db"))

        let items = CacheScanner.folderItems(fx.paths.cacheFolders)
        #expect(items.count == 1)   // empty or missing cache folders are not listed
        guard case .files(let urls) = items[0].action else { Issue.record("expected files"); return }
        #expect(Set(urls.map(\.lastPathComponent)) == ["repositories", "manifests.db"])

        let remover = Remover(guardian: SafetyGuard(paths: fx.paths), mode: .permanent, dryRun: false)
        #expect(await remover.remove(items[0]).success)
        #expect(fx.exists(cache.url))
        #expect(FS.children(of: cache.url).isEmpty)
    }

    @Test func codingAgentsKeepTheVersionTheSelectedXcodeUses() throws {
        for version in ["2.1.59", "2.1.81", "2.1.294"] {
            try fx.makeFile(fx.paths.codingAgents.appending(path: "\(version)/claude"))
        }
        for (build, version) in [("17E192", "2.1.81"), ("27B48", "2.1.294")] {
            let folder = try fx.makeDir(fx.paths.codingAgentXcodeVersions.appending(path: build))
            try FileManager.default.createSymbolicLink(
                at: folder.appending(path: "claude"),
                withDestinationURL: fx.paths.codingAgents.appending(path: version))
        }

        let items = ExtrasScanner.agentItems(paths: fx.paths, xcodeBuild: "27B48")
        #expect(items.count == 3)
        #expect(items.first { $0.version == "2.1.294" }?.isRemovable == false)
        #expect(items.first { $0.version == "2.1.59" }?.isRemovable == true)

        let old = try #require(items.first { $0.version == "2.1.81" })
        guard case .files(let urls) = old.action else { Issue.record("expected files"); return }
        #expect(Set(urls.map(\.lastPathComponent)) == ["2.1.81", "17E192"])

        // Unknown Xcode build: keep everything any Xcode links to.
        let cautious = ExtrasScanner.agentItems(paths: fx.paths, xcodeBuild: nil)
        #expect(cautious.filter(\.isRemovable).compactMap(\.version) == ["2.1.59"])
    }

    @Test func sizeCalculatorCountsAllocatedBytes() throws {
        let folder = try fx.makeDir(fx.home.appending(path: "Sized"))
        try fx.makeFile(folder.appending(path: "a"), bytes: 10_000)
        try fx.makeFile(folder.appending(path: "sub/b"), bytes: 20_000)
        let size = SizeCalculator.allocatedSize(of: folder)
        #expect(size >= 30_000)
        #expect(size < 200_000)
    }

    @Test func projectScanFindsOnlyBuildFolders() async throws {
        let root = try fx.makeDir(fx.home.appending(path: "Code"))
        let package = try fx.makeDir(root.appending(path: "Pkg"))
        try fx.makeFile(package.appending(path: "Package.swift"))
        try fx.makeFile(package.appending(path: ".build/debug/x.o"))
        try fx.makeFile(package.appending(path: "Sources/Pkg/main.swift"))

        let app = try fx.makeDir(root.appending(path: "Group/App"))
        try fx.makeDir(app.appending(path: "App.xcodeproj"))
        try fx.makeFile(app.appending(path: "DerivedData/Build/x"))
        try fx.makeFile(app.appending(path: "Podfile"))
        try fx.makeFile(app.appending(path: "Pods/Lib/lib.swift"))
        try fx.makeFile(app.appending(path: "App/ContentView.swift"))

        try fx.makeFile(root.appending(path: "Notes/.build/keep.txt"))   // no Package.swift beside it

        let items = await ProjectScanner().scan(ScanContext(paths: fx.paths, projectRoots: [root]))
        // The temp folder is reported as /private/var/… by directory listings; compare resolved paths.
        let prefix = root.resolvingSymlinksInPath().path + "/"
        let found = Set(items.compactMap { $0.path?.resolvingSymlinksInPath().path.replacingOccurrences(of: prefix, with: "") })
        #expect(found == ["Pkg/.build", "Group/App/DerivedData", "Group/App/Pods"])
        #expect(items.first { $0.path?.lastPathComponent == "Pods" }?.risk == .caution)

        let guardian = SafetyGuard(paths: fx.paths, projectRoots: [root])
        for item in items {
            guard case .files(let urls) = item.action else { continue }
            for url in urls { #expect(throws: Never.self) { try guardian.validate(url) } }
        }
    }

    @Test func projectScanSkipsFoldersTrackedByGit() async throws {
        let root = try fx.makeDir(fx.home.appending(path: "Code"))
        let app = try fx.makeDir(root.appending(path: "App"))
        try fx.makeFile(app.appending(path: "Podfile"))
        try fx.makeFile(app.appending(path: "Pods/Lib/lib.swift"))

        func git(_ args: String...) async throws {
            let out = try await ProcessRunner.run("/usr/bin/git", ["-C", app.path] + args)
            #expect(out.succeeded, "git \(args) failed: \(out.stderr)")
        }
        try await git("init", "-q")
        try await git("add", "Pods")

        let items = await ProjectScanner().scan(ScanContext(paths: fx.paths, projectRoots: [root]))
        #expect(items.isEmpty)
    }
}
