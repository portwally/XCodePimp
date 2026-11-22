import Foundation
import Testing
@testable import XCodePimp

@Suite struct SimctlTests {
    // Shapes captured from `xcrun simctl runtime list -j` and `xcrun simctl list devices -j` (Xcode 27.2).
    static let runtimeJSON = Data("""
    {
      "6BB55B07-F0FC-473C-9E14-2BC8533617DD" : {
        "build" : "23F77", "deletable" : true, "identifier" : "6BB55B07-F0FC-473C-9E14-2BC8533617DD",
        "kind" : "Patchable Cryptex Disk Image", "lastUsedAt" : "2026-11-21T17:21:44Z",
        "mountPath" : "/Library/Developer/CoreSimulator/Volumes/iOS_23F77",
        "platformIdentifier" : "com.apple.platform.iphonesimulator",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "signatureState" : "Verified", "sizeBytes" : 8494282293, "state" : "Ready",
        "supportedArchitectures" : [ "arm64" ], "version" : "26.5"
      },
      "032C95BF-2F80-4E1B-A960-DBE5DA52FC1E" : {
        "build" : "24B114", "deletable" : true, "identifier" : "032C95BF-2F80-4E1B-A960-DBE5DA52FC1E",
        "lastUsedAt" : "2026-11-21T22:36:29Z",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
        "sizeBytes" : 8311163745, "state" : "Ready", "version" : "27.2"
      },
      "60DEBE5F-0C2D-49A5-B18D-45AB15A6CD37" : {
        "build" : "24B91016s", "deletable" : true, "identifier" : "60DEBE5F-0C2D-49A5-B18D-45AB15A6CD37",
        "lastUsedAt" : "2026-10-01T10:00:00Z",
        "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
        "sizeBytes" : 8300000000, "state" : "Ready", "version" : "27.2"
      }
    }
    """.utf8)

    static let deviceJSON = Data("""
    {
      "devices" : {
        "com.apple.CoreSimulator.SimRuntime.iOS-27-2" : [
          {
            "dataPath" : "/Users/x/Library/Developer/CoreSimulator/Devices/16EA25C1-FD40-4F08-A0D5-A0269E2EA279/data",
            "dataPathSize" : 5104197632, "logPathSize" : 516096,
            "udid" : "16EA25C1-FD40-4F08-A0D5-A0269E2EA279", "lastUsedAt" : "2026-11-21T07:17:28Z",
            "isAvailable" : true, "deviceTypeIdentifier" : "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro-Max",
            "state" : "Shutdown", "name" : "iPhone 18 Pro Max"
          },
          {
            "udid" : "0891FBED-FBEA-47DF-8569-E56AE0A11BD5", "isAvailable" : true,
            "state" : "Booted", "name" : "Screens"
          }
        ],
        "com.apple.CoreSimulator.SimRuntime.iOS-17-0" : [
          {
            "udid" : "B2B57B17-2800-4B0E-BF7A-43DF67C0A1AB", "isAvailable" : false,
            "availabilityError" : "runtime profile not found", "state" : "Shutdown", "name" : "Old iPhone"
          }
        ]
      }
    }
    """.utf8)

    @Test func runtimeNames() {
        #expect(Simctl.displayName(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-2") == "iOS 27.2")
        #expect(Simctl.displayName(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.watchOS-11-0") == "watchOS 11.0")
        #expect(Simctl.platform(runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.xrOS-2-1") == "xrOS")
    }

    @Test func runtimesDecodeAndFlagDuplicates() throws {
        let runtimes = try Simctl.parseRuntimes(Self.runtimeJSON)
        let devices = try Simctl.parseDevices(Self.deviceJSON)
        #expect(runtimes.count == 3)

        let items = RuntimeScanner.items(runtimes: runtimes, devices: devices)
        let release = try #require(items.first { $0.version == "24B114" })
        let beta = try #require(items.first { $0.version == "24B91016s" })
        let other = try #require(items.first { $0.version == "23F77" })

        #expect(release.title == "iOS 27.2 (24B114)")
        #expect(release.size == 8_311_163_745)
        #expect(!release.flags.contains(.duplicate))
        #expect(beta.flags.contains(.duplicate))
        #expect(other.flags.isEmpty)
        #expect(other.detail == "No simulators use this version")
        #expect(beta.action == .simctl(["runtime", "delete", "60DEBE5F-0C2D-49A5-B18D-45AB15A6CD37"]))
        #expect(items.allSatisfy { $0.risk == .caution })
    }

    @Test func devicesDecodeWithBootedAndUnavailableHandling() throws {
        let items = DeviceScanner.items(devices: try Simctl.parseDevices(Self.deviceJSON))
        #expect(items.count == 3)

        let normal = try #require(items.first { $0.title == "iPhone 18 Pro Max" })
        #expect(normal.size == Int64(5_104_713_728))
        #expect(normal.action == .simctl(["delete", "16EA25C1-FD40-4F08-A0D5-A0269E2EA279"]))
        #expect(normal.secondary?.action == .simctl(["erase", "16EA25C1-FD40-4F08-A0D5-A0269E2EA279"]))
        #expect(normal.risk == .caution)

        let booted = try #require(items.first { $0.title == "Screens" })
        #expect(!booted.isRemovable)
        #expect(booted.flags.contains(.booted))

        let unavailable = try #require(items.first { $0.title == "Old iPhone" })
        #expect(unavailable.flags.contains(.unavailable))
        #expect(unavailable.risk == .safe)

        for item in items {
            if case .simctl(let args) = item.action { #expect(Simctl.isAllowedDestructive(args)) }
            if case .simctl(let args)? = item.secondary?.action { #expect(Simctl.isAllowedDestructive(args)) }
        }
    }
}

@Suite struct SuggestionTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func item(_ id: String, _ category: CategoryID, risk: Risk = .safe, daysAgo: Double? = nil,
                      flags: Set<ItemFlag> = [], removable: Bool = true) -> CleanableItem {
        CleanableItem(
            id: id, category: category, title: id, detail: "", path: nil, size: 1,
            lastUsed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
            risk: risk, action: removable ? .files([URL(fileURLWithPath: "/tmp/\(id)")]) : .none, flags: flags
        )
    }

    @Test func suggestsOnlyStaleOrphanedAndSupersededItems() {
        let items = [
            item("fresh", .derivedData, daysAgo: 2),
            item("stale", .derivedData, daysAgo: 45),
            item("orphan", .derivedData, daysAgo: 1, flags: [.orphaned]),
            item("shared", .derivedData, daysAgo: 400, flags: [.sharedCache]),
            item("gone-sim", .devices, flags: [.unavailable]),
            item("live-sim", .devices, risk: .caution, daysAgo: 300),
            item("dup-rt", .runtimes, risk: .caution, daysAgo: 1, flags: [.duplicate]),
            item("old-rt", .runtimes, risk: .caution, daysAgo: 120),
            item("used-rt", .runtimes, risk: .caution, daysAgo: 60),
            item("old-ds", .deviceSupport, flags: [.superseded]),
            item("new-ds", .deviceSupport, risk: .caution),
            item("logs", .caches, flags: [.log]),
            item("spm", .caches),
            item("archive", .archives, risk: .keep, daysAgo: 900),
            item("booted", .devices, flags: [.unavailable], removable: false),
        ]
        let suggestions = SuggestionEngine.suggestions(for: items, staleDays: 30, now: now)
        #expect(Set(suggestions.keys) == ["stale", "orphan", "gone-sim", "dup-rt", "old-rt", "old-ds", "logs"])

        // Runtimes need a download afterwards, so they are offered but never ticked for the user.
        let preselected = SuggestionEngine.preselected(suggestions, items: items)
        #expect(preselected == ["stale", "orphan", "gone-sim", "old-ds", "logs"])
    }
}
