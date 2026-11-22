import Foundation

/// One entry of `xcrun simctl runtime list -j`.
struct SimRuntimeImage: Decodable, Sendable, Hashable {
    let identifier: String
    let build: String?
    let version: String?
    let runtimeIdentifier: String?
    let platformIdentifier: String?
    let sizeBytes: Int64?
    let lastUsedAt: String?
    let deletable: Bool?
    let state: String?
    let kind: String?
}

/// One device of `xcrun simctl list devices -j`.
struct SimDevice: Decodable, Sendable, Hashable {
    let udid: String
    let name: String
    let state: String?
    let isAvailable: Bool?
    let availabilityError: String?
    let dataPath: String?
    let dataPathSize: Int64?
    let logPath: String?
    let logPathSize: Int64?
    let lastUsedAt: String?
    let lastBootedAt: String?
    let deviceTypeIdentifier: String?
}

struct SimDeviceEntry: Sendable, Hashable {
    let runtimeIdentifier: String
    let device: SimDevice
}

enum Simctl {
    private struct DeviceList: Decodable {
        let devices: [String: [SimDevice]]
    }

    static func parseRuntimes(_ data: Data) throws -> [SimRuntimeImage] {
        let decoded = try JSONDecoder().decode([String: SimRuntimeImage].self, from: data)
        return decoded.values.sorted { ($0.version ?? "", $0.build ?? "") < ($1.version ?? "", $1.build ?? "") }
    }

    static func parseDevices(_ data: Data) throws -> [SimDeviceEntry] {
        let decoded = try JSONDecoder().decode(DeviceList.self, from: data)
        return decoded.devices
            .sorted { $0.key < $1.key }
            .flatMap { runtime, devices in devices.map { SimDeviceEntry(runtimeIdentifier: runtime, device: $0) } }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2" → "iOS 27.2"
    static func displayName(runtimeIdentifier: String) -> String {
        let last = runtimeIdentifier.split(separator: ".").last.map(String.init) ?? runtimeIdentifier
        guard let dash = last.firstIndex(of: "-") else { return last }
        let platform = last[..<dash]
        let version = last[last.index(after: dash)...].replacingOccurrences(of: "-", with: ".")
        return "\(platform) \(version)"
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-27-2" → "iOS"
    static func platform(runtimeIdentifier: String) -> String {
        displayName(runtimeIdentifier: runtimeIdentifier).split(separator: " ").first.map(String.init) ?? "Simulator"
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        return try? Date(string, strategy: .iso8601)
    }

    static func run(_ arguments: [String]) async throws -> ProcessRunner.Output {
        try await ProcessRunner.run("/usr/bin/xcrun", ["simctl"] + arguments)
    }

    static func runtimes() async -> [SimRuntimeImage] {
        guard let output = try? await run(["runtime", "list", "-j"]), output.succeeded else { return [] }
        return (try? parseRuntimes(output.stdout)) ?? []
    }

    /// `set` is nil for the default device set, or "previews" / "testing".
    static func devices(set: String? = nil) async -> [SimDeviceEntry] {
        let prefix = set.map { ["--set", $0] } ?? []
        guard let output = try? await run(prefix + ["list", "devices", "-j"]), output.succeeded else { return [] }
        return (try? parseDevices(output.stdout)) ?? []
    }

    // MARK: Allowed destructive commands

    private static func isUUID(_ string: String) -> Bool { UUID(uuidString: string) != nil }

    /// Only these exact command shapes may ever be executed on the user's behalf.
    static func isAllowedDestructive(_ arguments: [String]) -> Bool {
        switch arguments.count {
        case 2:
            return ["delete", "erase"].contains(arguments[0]) && isUUID(arguments[1])
        case 3:
            return arguments[0] == "runtime" && arguments[1] == "delete" && isUUID(arguments[2])
        case 4:
            return arguments[0] == "--set" && ["previews", "testing"].contains(arguments[1])
                && arguments[2] == "delete" && arguments[3] == "all"
        default:
            return false
        }
    }
}
