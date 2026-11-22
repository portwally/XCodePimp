import Foundation
import SwiftUI

/// How much it hurts to lose an item.
enum Risk: Int, Sendable, Codable, Comparable, CaseIterable {
    /// Rebuilt or re-created automatically.
    case safe
    /// Has to be downloaded again, or loses data some people care about.
    case caution
    /// Cannot be regenerated. Never preselected.
    case keep

    static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .safe: "Safe"
        case .caution: "Caution"
        case .keep: "Keep"
        }
    }

    var explanation: String {
        switch self {
        case .safe: "Xcode rebuilds this automatically."
        case .caution: "Needs a new download or loses local data."
        case .keep: "Cannot be regenerated."
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .keep: .red
        }
    }
}

enum CategoryID: String, CaseIterable, Identifiable, Sendable, Codable {
    case derivedData, runtimes, devices, deviceSupport, archives, caches, extras, projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .derivedData: "Derived Data"
        case .runtimes: "Simulator Runtimes"
        case .devices: "Simulator Devices"
        case .deviceSupport: "Device Support"
        case .archives: "Archives"
        case .caches: "Caches & Logs"
        case .extras: "Xcode Extras"
        case .projects: "Project Folders"
        }
    }

    var symbol: String {
        switch self {
        case .derivedData: "hammer"
        case .runtimes: "opticaldiscdrive"
        case .devices: "iphone"
        case .deviceSupport: "cable.connector"
        case .archives: "archivebox"
        case .caches: "tray.full"
        case .extras: "sparkles.rectangle.stack"
        case .projects: "folder"
        }
    }

    var color: Color {
        switch self {
        case .derivedData: .blue
        case .runtimes: .purple
        case .devices: .indigo
        case .deviceSupport: .teal
        case .archives: .red
        case .caches: .orange
        case .extras: .pink
        case .projects: .green
        }
    }

    var blurb: String {
        switch self {
        case .derivedData:
            "Build products, indexes and module caches. Xcode rebuilds them on the next build; your source code is never stored here."
        case .runtimes:
            "Downloaded simulator operating systems. Removed through Xcode's own simctl; deleting one means downloading it again when you need it."
        case .devices:
            "Individual simulators and the apps and data installed in them. Removed through simctl."
        case .deviceSupport:
            "Debug symbols copied from each iPhone, iPad, Watch or Apple TV you connected. Xcode copies them again the next time the device is attached."
        case .archives:
            "Builds you archived for distribution, including the dSYMs needed to symbolicate crash reports. These cannot be regenerated."
        case .caches:
            "Documentation, package and tool caches plus simulator and device logs."
        case .extras:
            "Newer Xcode data: old versions of the coding-assistant agent and Organizer downloads."
        case .projects:
            "Build folders inside the project folders you choose. Only regenerable folders that sit next to a project file and are not tracked by git are listed."
        }
    }
}

/// What actually happens when an item is cleaned.
enum RemovalAction: Sendable, Hashable {
    /// Move these files to the Trash (or delete them). Every URL passes through `SafetyGuard`.
    case files([URL])
    /// Run `xcrun simctl <arguments>`. Arguments are checked against a fixed set of shapes.
    case simctl([String])
    /// Shown for information only.
    case none
}

enum ItemFlag: String, Sendable, Hashable {
    case orphaned, unavailable, booted, log, superseded, sharedCache, infoOnly, duplicate
}

struct SecondaryAction: Sendable, Hashable {
    let label: String
    let action: RemovalAction
}

struct CleanableItem: Identifiable, Sendable, Hashable {
    let id: String
    let category: CategoryID
    var title: String
    var detail: String
    /// Location shown to the user and revealed in Finder.
    var path: URL?
    /// Allocated bytes on disk; `nil` while still being measured.
    var size: Int64?
    var lastUsed: Date?
    var risk: Risk
    var action: RemovalAction
    var badge: String?
    var flags: Set<ItemFlag> = []
    /// Items sharing a group are alternatives of each other (same device, same runtime version).
    var group: String?
    var version: String?
    var secondary: SecondaryAction?

    var isRemovable: Bool { action != .none }

    /// Paths whose size has to be measured for this item.
    var measureURLs: [URL] {
        if case .files(let urls) = action { return urls }
        return path.map { [$0] } ?? []
    }

    // Sort keys for the table.
    var sizeSort: Int64 { size ?? -1 }
    var lastUsedSort: Date { lastUsed ?? .distantPast }
    var riskSort: Int { risk.rawValue }
}

extension Int64 {
    var byteText: String { formatted(.byteCount(style: .file)) }
}
