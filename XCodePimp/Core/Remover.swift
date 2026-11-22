import Foundation

struct RemovalOutcome: Sendable {
    let itemID: String
    let title: String
    let category: CategoryID
    let size: Int64
    let success: Bool
    let dryRun: Bool
    let message: String
}

/// Carries out a removal. Files always go through `SafetyGuard`; simulators always go through simctl.
struct Remover: Sendable {
    enum Mode: String, Sendable, Codable {
        case trash, permanent
    }

    let guardian: SafetyGuard
    let mode: Mode
    let dryRun: Bool

    func remove(_ item: CleanableItem, using override: RemovalAction? = nil) async -> RemovalOutcome {
        let action = override ?? item.action
        func outcome(_ success: Bool, _ message: String) -> RemovalOutcome {
            RemovalOutcome(itemID: item.id, title: item.title, category: item.category, size: item.size ?? 0,
                           success: success, dryRun: dryRun, message: message)
        }

        switch action {
        case .none:
            return outcome(false, "This item is shown for information only.")

        case .files(let urls):
            // Validate everything before touching anything, so a bad path aborts the whole item.
            let validated: [URL]
            do {
                validated = try urls.map { try guardian.validate($0) }
            } catch {
                return outcome(false, error.localizedDescription)
            }
            if dryRun {
                return outcome(true, "Dry run: would \(mode == .trash ? "move to Trash" : "delete") \(validated.count) item(s).")
            }
            var failures: [String] = []
            for url in validated {
                do {
                    switch mode {
                    case .trash: try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    case .permanent: try FileManager.default.removeItem(at: url)
                    }
                } catch {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if failures.isEmpty {
                return outcome(true, mode == .trash ? "Moved to Trash." : "Deleted.")
            }
            return outcome(false, failures.joined(separator: " "))

        case .simctl(let arguments):
            guard Simctl.isAllowedDestructive(arguments) else {
                return outcome(false, "Refused to run an unexpected simctl command.")
            }
            if dryRun {
                return outcome(true, "Dry run: would run xcrun simctl \(arguments.joined(separator: " ")).")
            }
            do {
                let result = try await Simctl.run(arguments)
                if result.succeeded { return outcome(true, "Removed with simctl.") }
                let reason = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return outcome(false, reason.isEmpty ? "simctl exited with status \(result.status)." : reason)
            } catch {
                return outcome(false, error.localizedDescription)
            }
        }
    }
}
