import Darwin
import Foundation

// Shared lifecycle state is protected by condition; the worker alone owns the Process and stderr.
final class ProcessRunner: @unchecked Sendable {
    struct Result {
        let status: Int32
        let reason: Process.TerminationReason
        let standardError: Data
    }

    enum Failure: Error, Equatable {
        case timedOut
    }

    private enum State { case ready, scheduled, running, finished }
    private let condition = NSCondition()
    private var state = State.ready
    private var cancelled = false
    private var launchedPID: Int32?
    static let errorLimit = 64 * 1024

    var processIdentifier: Int32? {
        condition.lock()
        defer { condition.unlock() }
        return launchedPID
    }

    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> Result {
        precondition(timeout > 0 && timeout.isFinite)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                condition.lock()
                precondition(state == .ready, "A process runner can only be used once.")
                state = .scheduled
                condition.unlock()
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try self.execute(
                            executable: executable, arguments: arguments, timeout: timeout)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    func cancel() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        condition.unlock()
    }

    func cancelAndWait() {
        condition.lock()
        cancelled = true
        condition.broadcast()
        while state == .scheduled || state == .running { condition.wait() }
        condition.unlock()
    }

    private func execute(executable: URL, arguments: [String], timeout: TimeInterval) throws -> Result {
        defer {
            condition.lock()
            state = .finished
            condition.broadcast()
            condition.unlock()
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        let descriptor = errors.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        condition.lock()
        if cancelled {
            condition.unlock()
            throw CancellationError()
        }
        condition.unlock()
        try process.run()
        condition.lock()
        state = .running
        launchedPID = process.processIdentifier
        condition.unlock()
        try? errors.fileHandleForWriting.close()

        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var stopReason: Error?
        var killDeadline: TimeInterval?
        var output = Data()
        while process.isRunning {
            drain(descriptor, into: &output)
            condition.lock()
            let shouldCancel = cancelled
            condition.unlock()
            let now = ProcessInfo.processInfo.systemUptime
            if stopReason == nil, shouldCancel || now >= deadline {
                stopReason = shouldCancel ? CancellationError() : Failure.timedOut
                process.terminate()
                killDeadline = now + 0.25
            }
            if let limit = killDeadline, now >= limit, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                killDeadline = nil
            }
            condition.lock()
            _ = condition.wait(until: Date(timeIntervalSinceNow: 0.01))
            condition.unlock()
        }
        process.waitUntilExit()
        // A descendant may retain stderr. Drain available bytes without ever waiting for EOF.
        drain(descriptor, into: &output)
        condition.lock()
        let wasCancelled = cancelled
        condition.unlock()
        if wasCancelled { throw CancellationError() }
        if let stopReason { throw stopReason }
        return Result(
            status: process.terminationStatus, reason: process.terminationReason, standardError: output)
    }

    private func drain(_ descriptor: Int32, into output: inout Data) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        // Limit each pass so a continuous writer cannot prevent deadline or cancellation checks.
        for _ in 0..<16 {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count > 0 else { return }
            output.append(contentsOf: buffer.prefix(min(count, max(0, Self.errorLimit - output.count))))
        }
    }
}
