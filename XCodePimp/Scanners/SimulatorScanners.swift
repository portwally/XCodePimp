import Foundation

struct RuntimeScanner: CleanupScanner {
    let category = CategoryID.runtimes

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        async let runtimes = Simctl.runtimes()
        async let devices = Simctl.devices()
        return Self.items(runtimes: await runtimes, devices: await devices)
    }

    static func items(runtimes: [SimRuntimeImage], devices: [SimDeviceEntry]) -> [CleanableItem] {
        let deviceCounts = Dictionary(grouping: devices, by: \.runtimeIdentifier).mapValues(\.count)

        // Of several images for one OS version, the most recently used one is the keeper.
        var keeper: [String: String] = [:]
        for (identifier, group) in Dictionary(grouping: runtimes, by: { $0.runtimeIdentifier ?? $0.identifier }) where group.count > 1 {
            let best = group.max { a, b in
                let da = Simctl.date(a.lastUsedAt) ?? .distantPast
                let db = Simctl.date(b.lastUsedAt) ?? .distantPast
                return da == db ? (a.build ?? "") < (b.build ?? "") : da < db
            }
            keeper[identifier] = best?.identifier
        }

        return runtimes.map { runtime in
            let runtimeID = runtime.runtimeIdentifier ?? runtime.identifier
            let platform = runtime.runtimeIdentifier.map(Simctl.platform(runtimeIdentifier:)) ?? "Simulator"
            let name = "\(platform) \(runtime.version ?? "?")" + (runtime.build.map { " (\($0))" } ?? "")
            let count = deviceCounts[runtimeID] ?? 0
            let isDuplicate = keeper[runtimeID].map { $0 != runtime.identifier } ?? false
            let deletable = runtime.deletable ?? true

            var flags: Set<ItemFlag> = []
            if isDuplicate { flags.insert(.duplicate) }
            if !deletable { flags.insert(.infoOnly) }
            if runtime.state.map({ $0 != "Ready" }) ?? false { flags.insert(.unavailable) }

            var detail = count == 0 ? "No simulators use this version" : "\(count) simulator\(count == 1 ? "" : "s") on this version"
            if !deletable { detail += " · bundled with Xcode" }

            return CleanableItem(
                id: "rt:" + runtime.identifier, category: .runtimes,
                title: name, detail: detail, path: nil,
                size: runtime.sizeBytes ?? 0,
                lastUsed: Simctl.date(runtime.lastUsedAt),
                risk: .caution,
                action: deletable ? .simctl(["runtime", "delete", runtime.identifier]) : .none,
                badge: isDuplicate ? "Duplicate build" : (flags.contains(.unavailable) ? runtime.state : nil),
                flags: flags, group: runtimeID, version: runtime.build
            )
        }
    }
}

struct DeviceScanner: CleanupScanner {
    let category = CategoryID.devices

    func scan(_ context: ScanContext) async -> [CleanableItem] {
        async let main = Simctl.devices()
        async let previews = Simctl.devices(set: "previews")
        async let testing = Simctl.devices(set: "testing")

        var items = Self.items(devices: await main)
        if let item = Self.setItem(set: "previews", title: "SwiftUI preview simulators", devices: await previews) { items.append(item) }
        if let item = Self.setItem(set: "testing", title: "Parallel-testing simulator clones", devices: await testing) { items.append(item) }
        return items
    }

    static func items(devices: [SimDeviceEntry]) -> [CleanableItem] {
        devices.map { entry in
            let device = entry.device
            let booted = (device.state ?? "Shutdown") != "Shutdown"
            let unavailable = device.isAvailable == false
            let model = device.deviceTypeIdentifier?
                .split(separator: ".").last
                .map { $0.replacingOccurrences(of: "-", with: " ") }

            var detailParts = [Simctl.displayName(runtimeIdentifier: entry.runtimeIdentifier)]
            if let model, model != device.name { detailParts.append(model) }
            if unavailable { detailParts.append("runtime not installed") }

            var flags: Set<ItemFlag> = []
            if booted { flags.insert(.booted) }
            if unavailable { flags.insert(.unavailable) }

            let knownSize: Int64? = device.dataPathSize.map { $0 + (device.logPathSize ?? 0) }
            let folder = device.dataPath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }

            return CleanableItem(
                id: "dev:" + device.udid, category: .devices,
                title: device.name, detail: detailParts.joined(separator: " · "),
                path: folder, size: knownSize,
                lastUsed: Simctl.date(device.lastUsedAt ?? device.lastBootedAt),
                risk: unavailable ? .safe : .caution,
                // A running simulator is never deleted from under the user.
                action: booted ? .none : .simctl(["delete", device.udid]),
                badge: booted ? "Running" : (unavailable ? "Unavailable" : nil),
                flags: flags, group: entry.runtimeIdentifier,
                secondary: booted ? nil : SecondaryAction(label: "Erase Content and Settings", action: .simctl(["erase", device.udid]))
            )
        }
    }

    static func setItem(set: String, title: String, devices: [SimDeviceEntry]) -> CleanableItem? {
        guard !devices.isEmpty else { return nil }
        let size = devices.reduce(Int64(0)) { $0 + ($1.device.dataPathSize ?? 0) + ($1.device.logPathSize ?? 0) }
        let running = devices.contains { ($0.device.state ?? "Shutdown") != "Shutdown" }
        return CleanableItem(
            id: "devset:" + set, category: .devices,
            title: title, detail: "\(devices.count) simulator\(devices.count == 1 ? "" : "s") created automatically by Xcode",
            path: nil, size: size,
            lastUsed: devices.compactMap { Simctl.date($0.device.lastUsedAt ?? $0.device.lastBootedAt) }.max(),
            risk: .safe,
            action: running ? .none : .simctl(["--set", set, "delete", "all"]),
            badge: running ? "Running" : nil,
            flags: running ? [.booted] : []
        )
    }
}
