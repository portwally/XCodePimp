import Foundation

enum ProcessRunner {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: String

        var succeeded: Bool { status == 0 }
        var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = Data()
        func set(_ data: Data) { lock.withLock { storage = data } }
        func get() -> Data { lock.withLock { storage } }
    }

    /// Runs a tool to completion without blocking the caller's executor.
    static func run(_ executable: String, _ arguments: [String]) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain both pipes at once so a chatty tool cannot fill one and stall.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.set(err.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: Output(
                    status: process.terminationStatus,
                    stdout: outData,
                    stderr: String(decoding: errBox.get(), as: UTF8.self)
                ))
            }
        }
    }
}
