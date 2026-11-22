import AppKit
import Foundation
import Observation

enum SidebarItem: Hashable {
    case overview, suggested, history
    case category(CategoryID)
}

struct HistoryEntry: Codable, Identifiable, Sendable {
    var id = UUID()
    let date: Date
    let title: String
    let category: CategoryID
    let size: Int64
    let success: Bool
    let dryRun: Bool
    let message: String
}

struct CleanRequest: Identifiable {
    let id = UUID()
    let items: [CleanableItem]
    /// Set when a non-default action (e.g. erase instead of delete) was asked for.
    var override: RemovalAction?
    var verb = "Clean"

    var totalSize: Int64 { items.reduce(0) { $0 + ($1.size ?? 0) } }
}

@MainActor
@Observable
final class AppModel {
    // MARK: State

    var selection: SidebarItem? = .overview
    private(set) var itemsByCategory: [CategoryID: [CleanableItem]] = [:]
    private(set) var scanning: Set<CategoryID> = []
    private(set) var suggestions: [String: String] = [:]
    var checked: Set<String> = []
    var pendingClean: CleanRequest?
    private(set) var isCleaning = false
    private(set) var cleanProgress: String?
    var resultMessage: String?
    private(set) var history: [HistoryEntry] = []
    private(set) var hasScanned = false

    // MARK: Settings

    var staleDays: Int { didSet { defaults.set(staleDays, forKey: Keys.staleDays); refreshSuggestions() } }
    var permanentDelete: Bool { didSet { defaults.set(permanentDelete, forKey: Keys.permanentDelete) } }
    var dryRun: Bool { didSet { defaults.set(dryRun, forKey: Keys.dryRun) } }
    var projectRoots: [URL] {
        didSet { defaults.set(projectRoots.map(\.path), forKey: Keys.projectRoots) }
    }

    private enum Keys {
        static let staleDays = "staleDays"
        static let permanentDelete = "permanentDelete"
        static let dryRun = "dryRun"
        static let projectRoots = "projectRoots"
    }

    private let defaults: UserDefaults
    private let paths: Paths
    private var scanGeneration = 0

    init(defaults: UserDefaults = .standard, paths: Paths = .live) {
        self.defaults = defaults
        self.paths = paths
        let days = defaults.integer(forKey: Keys.staleDays)
        self.staleDays = days > 0 ? days : 30
        self.permanentDelete = defaults.bool(forKey: Keys.permanentDelete)
        self.dryRun = defaults.bool(forKey: Keys.dryRun)
        self.projectRoots = (defaults.stringArray(forKey: Keys.projectRoots) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        self.history = Self.loadHistory()
    }

    /// True while unit tests host the app; no scanning of the real machine then.
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    // MARK: Derived values

    var allItems: [CleanableItem] { CategoryID.allCases.flatMap { itemsByCategory[$0] ?? [] } }

    func items(in category: CategoryID) -> [CleanableItem] { itemsByCategory[category] ?? [] }

    var suggestedItems: [CleanableItem] { allItems.filter { suggestions[$0.id] != nil } }

    var checkedItems: [CleanableItem] { allItems.filter { checked.contains($0.id) && $0.isRemovable } }

    var checkedSize: Int64 { checkedItems.reduce(0) { $0 + ($1.size ?? 0) } }

    func totalSize(_ category: CategoryID) -> Int64 {
        items(in: category).reduce(0) { $0 + ($1.size ?? 0) }
    }

    func reclaimableSize(_ category: CategoryID) -> Int64 {
        items(in: category).filter(\.isRemovable).reduce(0) { $0 + ($1.size ?? 0) }
    }

    var totalSize: Int64 { CategoryID.allCases.reduce(0) { $0 + totalSize($1) } }
    var suggestedSize: Int64 { suggestedItems.reduce(0) { $0 + ($1.size ?? 0) } }

    func isMeasuring(_ category: CategoryID) -> Bool {
        scanning.contains(category) || items(in: category).contains { $0.size == nil }
    }

    var isBusy: Bool { !scanning.isEmpty || isCleaning }

    var isXcodeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty
    }

    // MARK: Scanning

    func scanIfNeeded() async {
        guard !hasScanned, !Self.isRunningTests else { return }
        await scan()
    }

    func scan(only categories: Set<CategoryID>? = nil) async {
        hasScanned = true
        scanGeneration += 1
        let generation = scanGeneration
        let scanners = Scanners.all.filter { categories?.contains($0.category) ?? true }
        scanning.formUnion(scanners.map(\.category))

        let context = ScanContext(
            paths: paths,
            projectRoots: projectRoots,
            xcodeBuild: await ScanContext.currentXcodeBuild()
        )

        await withTaskGroup(of: (CategoryID, [CleanableItem]).self) { group in
            for scanner in scanners {
                group.addTask { (scanner.category, await scanner.scan(context)) }
            }
            for await (category, items) in group {
                guard generation == scanGeneration || categories != nil else { continue }
                itemsByCategory[category] = items
                scanning.remove(category)
                checked.formIntersection(Set(allItems.map(\.id)))
                refreshSuggestions()
                Task { await measure(category) }
            }
        }
        scanning.subtract(scanners.map(\.category))
    }

    /// Fills in sizes a few folders at a time, updating the list as each one finishes.
    private func measure(_ category: CategoryID) async {
        let pending = items(in: category).filter { $0.size == nil }
        guard !pending.isEmpty else { return }

        await withTaskGroup(of: (String, Int64).self) { group in
            var iterator = pending.makeIterator()
            func enqueue() {
                guard let item = iterator.next() else { return }
                let urls = item.measureURLs
                group.addTask { (item.id, await SizeCalculator.measure(urls)) }
            }
            for _ in 0..<4 { enqueue() }
            for await (id, size) in group {
                if let index = itemsByCategory[category]?.firstIndex(where: { $0.id == id }) {
                    itemsByCategory[category]?[index].size = size
                }
                enqueue()
            }
        }
    }

    private func refreshSuggestions() {
        suggestions = SuggestionEngine.suggestions(for: allItems, staleDays: staleDays)
    }

    // MARK: Selection

    func isChecked(_ item: CleanableItem) -> Bool { checked.contains(item.id) }

    func setChecked(_ item: CleanableItem, _ on: Bool) {
        guard item.isRemovable else { return }
        if on { checked.insert(item.id) } else { checked.remove(item.id) }
    }

    func check(_ items: [CleanableItem], where predicate: (CleanableItem) -> Bool = { _ in true }) {
        checked.formUnion(items.filter { $0.isRemovable && predicate($0) }.map(\.id))
    }

    func uncheck(_ items: [CleanableItem]) {
        checked.subtract(items.map(\.id))
    }

    func selectSafeSuggestions() {
        checked.formUnion(SuggestionEngine.preselected(suggestions, items: allItems))
    }

    // MARK: Cleaning

    func requestCleanChecked() {
        let items = checkedItems
        guard !items.isEmpty else { return }
        pendingClean = CleanRequest(items: items)
    }

    func requestSecondary(_ item: CleanableItem) {
        guard let secondary = item.secondary else { return }
        pendingClean = CleanRequest(items: [item], override: secondary.action, verb: secondary.label)
    }

    func perform(_ request: CleanRequest) async {
        guard !isCleaning else { return }
        isCleaning = true
        defer { isCleaning = false; cleanProgress = nil }

        let remover = Remover(
            guardian: SafetyGuard(paths: paths, projectRoots: projectRoots),
            mode: permanentDelete ? .permanent : .trash,
            dryRun: dryRun
        )

        var freed: Int64 = 0
        var failures = 0
        var touched: Set<CategoryID> = []

        for (index, item) in request.items.enumerated() {
            cleanProgress = "\(index + 1) of \(request.items.count): \(item.title)"
            let outcome = await remover.remove(item, using: request.override)
            history.insert(HistoryEntry(
                date: .now, title: outcome.title, category: outcome.category, size: outcome.size,
                success: outcome.success, dryRun: outcome.dryRun, message: outcome.message
            ), at: 0)

            if outcome.success {
                touched.insert(item.category)
                if !outcome.dryRun, request.override == nil {
                    freed += outcome.size
                    itemsByCategory[item.category]?.removeAll { $0.id == item.id }
                    checked.remove(item.id)
                }
            } else {
                failures += 1
            }
        }

        history = Array(history.prefix(500))
        saveHistory()
        refreshSuggestions()

        let count = request.items.count - failures
        if dryRun {
            resultMessage = "Dry run finished: \(count) item\(count == 1 ? "" : "s") would be removed. Nothing was changed."
        } else if failures == 0 {
            resultMessage = request.override == nil
                ? "Freed \(freed.byteText) from \(count) item\(count == 1 ? "" : "s")."
                : "\(request.verb) finished."
        } else {
            resultMessage = "\(count) succeeded, \(failures) failed. See History for the reasons."
        }

        // Simulator state lives in CoreSimulator, so re-read it instead of trusting our own bookkeeping.
        if !dryRun {
            var rescan = touched.intersection([.runtimes, .devices, .extras])
            if rescan.contains(.runtimes) { rescan.formUnion([.devices, .caches]) }
            if rescan.contains(.devices) { rescan.insert(.caches) }
            if !rescan.isEmpty { await scan(only: rescan) }
        }
    }

    // MARK: Project folders

    func addProjectRoots(_ urls: [URL]) {
        let existing = Set(projectRoots.map(\.path))
        projectRoots += urls.filter { !existing.contains($0.path) }
        Task { await scan(only: [.projects]) }
    }

    func removeProjectRoot(_ url: URL) {
        projectRoots.removeAll { $0.path == url.path }
        Task { await scan(only: [.projects]) }
    }

    func chooseProjectRoots() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders that contain your Xcode projects."
        if panel.runModal() == .OK { addProjectRoots(panel.urls) }
    }

    // MARK: History

    func clearHistory() {
        history = []
        saveHistory()
    }

    private static var historyURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return support.appending(path: "XCodePimp/history.json")
    }

    private static func loadHistory() -> [HistoryEntry] {
        guard !isRunningTests, let url = historyURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func saveHistory() {
        guard !Self.isRunningTests, let url = Self.historyURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(history) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
