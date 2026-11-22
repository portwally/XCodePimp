import Foundation

/// Decides which items are worth offering in the "Suggested" view, and why.
enum SuggestionEngine {
    /// Returns item id → reason. Only removable items are ever suggested.
    static func suggestions(for items: [CleanableItem], staleDays: Int, now: Date = .now) -> [String: String] {
        let staleCutoff = now.addingTimeInterval(-Double(staleDays) * 86_400)
        let runtimeCutoff = now.addingTimeInterval(-Double(staleDays) * 3 * 86_400)
        var result: [String: String] = [:]

        for item in items where item.isRemovable {
            switch item.category {
            case .derivedData:
                if item.flags.contains(.orphaned) {
                    // The detail is the project path this build data was made from.
                    let location = (item.detail as NSString).abbreviatingWithTildeInPath
                    result[item.id] = item.flags.contains(.duplicate)
                        ? "Built from a copy that was deleted: \(location)"
                        : "The project no longer exists: \(location)"
                } else if !item.flags.contains(.sharedCache), let used = item.lastUsed, used < staleCutoff {
                    result[item.id] = "Not opened for \(staleDays) days"
                }
            case .devices:
                if item.flags.contains(.unavailable) {
                    result[item.id] = "Its runtime is no longer installed"
                }
            case .runtimes:
                if item.flags.contains(.duplicate) {
                    result[item.id] = "Another build of this version is installed and used more recently"
                } else if item.flags.contains(.unavailable) {
                    result[item.id] = "This runtime is unusable"
                } else if let used = item.lastUsed, used < runtimeCutoff {
                    result[item.id] = "Not used for \(staleDays * 3) days"
                }
            case .deviceSupport:
                if item.flags.contains(.superseded) {
                    result[item.id] = "A newer version exists for the same device"
                }
            case .caches:
                if item.flags.contains(.log) {
                    result[item.id] = "Old logs"
                }
            case .extras:
                if item.flags.contains(.superseded) {
                    result[item.id] = "Not used by the selected Xcode"
                }
            case .archives, .projects:
                break
            }
        }
        return result
    }

    /// Of the suggested items, only the risk-free ones start out ticked.
    static func preselected(_ suggestions: [String: String], items: [CleanableItem]) -> Set<String> {
        Set(items.filter { suggestions[$0.id] != nil && $0.risk == .safe }.map(\.id))
    }
}
