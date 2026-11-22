import Foundation
import Testing
@testable import XCodePimp

@Suite struct SafetyGuardTests {
    let fx: Fixture
    let guardian: SafetyGuard

    init() throws {
        fx = try Fixture()
        guardian = SafetyGuard(paths: fx.paths)
    }

    @Test func acceptsItemInsideDerivedData() throws {
        let folder = try fx.makeDir(fx.paths.derivedData.appending(path: "App-abc"))
        #expect(throws: Never.self) { try guardian.validate(folder) }
    }

    @Test func rejectsRootItself() throws {
        try fx.makeDir(fx.paths.derivedData)
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(fx.paths.derivedData) }
    }

    @Test func rejectsXcodeFolderAndHome() throws {
        try fx.makeDir(fx.paths.derivedData)
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(fx.paths.xcode) }
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(fx.home) }
    }

    @Test func rejectsPathOutsideRoots() throws {
        let project = try fx.makeDir(fx.home.appending(path: "Documents/MyApp"))
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(project) }
    }

    @Test func rejectsDotDotEscape() throws {
        try fx.makeDir(fx.paths.derivedData)
        let project = try fx.makeDir(fx.home.appending(path: "Documents/MyApp"))
        let sneaky = URL(fileURLWithPath: fx.paths.derivedData.path + "/../../../../Documents/MyApp")
        #expect(sneaky.standardizedFileURL.path == project.path)
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(sneaky) }
    }

    @Test func rejectsSymlinkItem() throws {
        try fx.makeDir(fx.paths.derivedData)
        let project = try fx.makeDir(fx.home.appending(path: "Documents/MyApp"))
        let link = fx.paths.derivedData.appending(path: "Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: project)
        #expect(throws: SafetyGuard.Violation.symlink(link.path)) { try guardian.validate(link) }
    }

    @Test func rejectsItemReachedThroughSymlinkedParent() throws {
        // DerivedData/Link -> ~/Documents ; DerivedData/Link/MyApp really lives in Documents.
        try fx.makeDir(fx.paths.derivedData)
        let documents = try fx.makeDir(fx.home.appending(path: "Documents"))
        try fx.makeDir(documents.appending(path: "MyApp"))
        let link = fx.paths.derivedData.appending(path: "Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: documents)
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(link.appending(path: "MyApp")) }
    }

    @Test func rejectsMissingItem() {
        #expect(throws: SafetyGuard.Violation.self) {
            try guardian.validate(fx.paths.derivedData.appending(path: "Nope"))
        }
    }

    @Test func rejectsProtectedUserData() throws {
        let profiles = try fx.makeDir(fx.paths.userData.appending(path: "Provisioning Profiles"))
        // Even if UserData were wrongly added as a root, protection wins.
        let loose = SafetyGuard(roots: [fx.paths.xcode], protected: fx.paths.protectedPaths)
        #expect(throws: SafetyGuard.Violation.protected(profiles.path)) { try loose.validate(profiles) }
        #expect(throws: SafetyGuard.Violation.self) { try loose.validate(fx.paths.userData) }
    }

    @Test func projectArtifactNeedsProjectFileNextToIt() throws {
        let root = try fx.makeDir(fx.home.appending(path: "Code"))
        let package = try fx.makeDir(root.appending(path: "Pkg"))
        try fx.makeFile(package.appending(path: "Package.swift"))
        let build = try fx.makeDir(package.appending(path: ".build"))
        let sources = try fx.makeDir(package.appending(path: "Sources"))
        let strayBuild = try fx.makeDir(root.appending(path: "Notes/.build"))

        let scoped = SafetyGuard(paths: fx.paths, projectRoots: [root])
        #expect(throws: Never.self) { try scoped.validate(build) }
        #expect(throws: SafetyGuard.Violation.self) { try scoped.validate(sources) }
        #expect(throws: SafetyGuard.Violation.self) { try scoped.validate(package) }
        #expect(throws: SafetyGuard.Violation.self) { try scoped.validate(strayBuild) }
        // Without the project root, even a real build folder is off limits.
        #expect(throws: SafetyGuard.Violation.self) { try guardian.validate(build) }
    }

    @Test func plainBuildFolderIsNotAnArtifact() throws {
        let project = try fx.makeDir(fx.home.appending(path: "Code/App"))
        try fx.makeDir(project.appending(path: "App.xcodeproj"))
        let userFolder = try fx.makeDir(project.appending(path: "build"))
        try fx.makeFile(userFolder.appending(path: "release-notes.txt"))
        #expect(ProjectArtifact.kind(of: userFolder) == nil)

        try fx.makeDir(userFolder.appending(path: "Debug-iphoneos"))
        #expect(ProjectArtifact.kind(of: userFolder) == .xcodeBuild)
    }
}

@Suite struct RemoverTests {
    let fx: Fixture

    init() throws { fx = try Fixture() }

    private func item(_ urls: [URL]) -> CleanableItem {
        CleanableItem(id: "t", category: .derivedData, title: "T", detail: "", path: urls.first,
                      size: 1, lastUsed: nil, risk: .safe, action: .files(urls))
    }

    @Test func dryRunRemovesNothing() async throws {
        let folder = try fx.makeDir(fx.paths.derivedData.appending(path: "App-abc"))
        let remover = Remover(guardian: SafetyGuard(paths: fx.paths), mode: .permanent, dryRun: true)
        let outcome = await remover.remove(item([folder]))
        #expect(outcome.success && outcome.dryRun)
        #expect(fx.exists(folder))
    }

    @Test func permanentDeleteRemovesOnlyTheItem() async throws {
        let folder = try fx.makeDir(fx.paths.derivedData.appending(path: "App-abc"))
        let other = try fx.makeDir(fx.paths.derivedData.appending(path: "Other-def"))
        let remover = Remover(guardian: SafetyGuard(paths: fx.paths), mode: .permanent, dryRun: false)
        let outcome = await remover.remove(item([folder]))
        #expect(outcome.success)
        #expect(!fx.exists(folder))
        #expect(fx.exists(other))
        #expect(fx.exists(fx.paths.derivedData))
    }

    @Test func oneBadPathAbortsTheWholeItem() async throws {
        let good = try fx.makeDir(fx.paths.derivedData.appending(path: "App-abc"))
        let bad = try fx.makeDir(fx.home.appending(path: "Documents/MyApp"))
        let remover = Remover(guardian: SafetyGuard(paths: fx.paths), mode: .permanent, dryRun: false)
        let outcome = await remover.remove(item([good, bad]))
        #expect(!outcome.success)
        #expect(fx.exists(good))
        #expect(fx.exists(bad))
    }

    @Test func infoOnlyItemIsRefused() async {
        let info = CleanableItem(id: "i", category: .extras, title: "I", detail: "", path: nil,
                                 size: 1, lastUsed: nil, risk: .caution, action: .none)
        let remover = Remover(guardian: SafetyGuard(paths: fx.paths), mode: .permanent, dryRun: false)
        #expect(await remover.remove(info).success == false)
    }

    @Test func simctlCommandShapes() {
        let id = "032C95BF-2F80-4E1B-A960-DBE5DA52FC1E"
        #expect(Simctl.isAllowedDestructive(["delete", id]))
        #expect(Simctl.isAllowedDestructive(["erase", id]))
        #expect(Simctl.isAllowedDestructive(["runtime", "delete", id]))
        #expect(Simctl.isAllowedDestructive(["--set", "previews", "delete", "all"]))
        #expect(!Simctl.isAllowedDestructive(["delete", "all"]))
        #expect(!Simctl.isAllowedDestructive(["erase", "all"]))
        #expect(!Simctl.isAllowedDestructive(["runtime", "delete", "all"]))
        #expect(!Simctl.isAllowedDestructive(["delete", "unavailable; rm -rf ~"]))
        #expect(!Simctl.isAllowedDestructive([]))
    }
}
