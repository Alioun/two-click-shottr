import Darwin
import Foundation
import Testing

@testable import TwoClickShottr

@Suite(.serialized)
struct ProcessRunnerTests {
    private let shell = URL(fileURLWithPath: "/bin/sh")
    private let sleep = URL(fileURLWithPath: "/bin/sleep")

    private func waitForPID(_ runner: ProcessRunner) async throws -> Int32 {
        let deadline = Date(timeIntervalSinceNow: 2)
        while runner.processIdentifier == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        return try #require(runner.processIdentifier)
    }

    private func expectReaped(_ pid: Int32) {
        let exists = kill(pid, 0)
        let existenceError = errno
        var status: Int32 = 0
        let waited = waitpid(pid, &status, WNOHANG)
        let waitError = errno
        #expect(exists == -1)
        #expect(existenceError == ESRCH)
        #expect(waited == -1)
        #expect(waitError == ECHILD)
    }

    @Test func normalFailureReportsExitStatusAndStderrAndReaps() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executable: shell,
            arguments: ["-c", "printf 'expected failure' >&2; exit 7"], timeout: 5)
        #expect(result.reason == .exit)
        #expect(result.status == 7)
        #expect(String(data: result.standardError, encoding: .utf8) == "expected failure")
        expectReaped(try #require(runner.processIdentifier))
    }

    @Test func noisyStderrIsDrainedWithoutUnboundedRetention() async throws {
        let runner = ProcessRunner()
        let result = try await runner.run(
            executable: shell,
            arguments: ["-c", "/usr/bin/head -c 1048576 /dev/zero >&2; exit 9"], timeout: 5)
        #expect(result.reason == .exit)
        #expect(result.status == 9)
        #expect(result.standardError.count == ProcessRunner.errorLimit)
        #expect(result.standardError.allSatisfy { $0 == 0 })
        expectReaped(try #require(runner.processIdentifier))
    }

    @Test func timeoutTerminatesAndReapsSleep() async throws {
        let runner = ProcessRunner()
        let start = Date()
        do {
            _ = try await runner.run(executable: sleep, arguments: ["30"], timeout: 0.1)
            Issue.record("The sleeping child unexpectedly completed.")
        } catch {
            #expect(error as? ProcessRunner.Failure == .timedOut)
        }
        #expect(Date().timeIntervalSince(start) < 2)
        expectReaped(try #require(runner.processIdentifier))
    }

    @Test func continuousStderrCannotStarveTimeout() async throws {
        let runner = ProcessRunner()
        let start = Date()
        do {
            _ = try await runner.run(
                executable: shell,
                arguments: ["-c", "exec /usr/bin/yes diagnostic >&2"], timeout: 0.1)
            Issue.record("The continuously writing child unexpectedly completed.")
        } catch {
            #expect(error as? ProcessRunner.Failure == .timedOut)
        }
        #expect(Date().timeIntervalSince(start) < 2)
        expectReaped(try #require(runner.processIdentifier))
    }

    @Test func taskCancellationTerminatesAndReapsSleep() async throws {
        let runner = ProcessRunner()
        let task = Task { try await runner.run(executable: sleep, arguments: ["30"], timeout: 5) }
        let pid = try await waitForPID(runner)
        let start = Date()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("The canceled child unexpectedly completed.")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(Date().timeIntervalSince(start) < 2)
        expectReaped(pid)
    }

    @Test func shutdownEscalatesWhenChildIgnoresTerminationAndWaitsForReaping() async throws {
        let ready = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: ready) }
        let runner = ProcessRunner()
        let task = Task {
            try await runner.run(
                executable: shell,
                arguments: [
                    "-c", "trap '' TERM; printf ready > \"$1\"; exec /bin/sleep 30", "test", ready.path,
                ], timeout: 5)
        }
        let pid = try await waitForPID(runner)
        let deadline = Date(timeIntervalSinceNow: 2)
        while !FileManager.default.fileExists(atPath: ready.path) && Date() < deadline {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: ready.path))
        let start = Date()
        runner.cancelAndWait()
        #expect(Date().timeIntervalSince(start) < 2)
        expectReaped(pid)
        do {
            _ = try await task.value
            Issue.record("The shutdown child unexpectedly completed.")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func cancellationBeforeLaunchDoesNotCreateChild() async throws {
        let runner = ProcessRunner()
        runner.cancelAndWait()
        do {
            _ = try await runner.run(executable: sleep, arguments: ["30"], timeout: 5)
            Issue.record("A canceled runner unexpectedly launched a child.")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(runner.processIdentifier == nil)
    }

    @Test func launchFailureLeavesShutdownSafe() async {
        let runner = ProcessRunner()
        do {
            _ = try await runner.run(
                executable: URL(fileURLWithPath: "/nonexistent/two-click-shottr-test"),
                arguments: [], timeout: 5)
            Issue.record("A nonexistent executable unexpectedly launched.")
        } catch {
            #expect(!(error is CancellationError))
        }
        runner.cancelAndWait()
        #expect(runner.processIdentifier == nil)
    }

    @Test func descendantHoldingStderrDoesNotDelayParentExit() async throws {
        let pidFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text) {
                kill(pid, SIGTERM)
            }
            try? FileManager.default.removeItem(at: pidFile)
        }
        let runner = ProcessRunner()
        let start = Date()
        let result = try await runner.run(
            executable: shell,
            arguments: [
                "-c", "/bin/sleep 3 & printf '%s' $! > \"$1\"; printf 'parent failure' >&2; exit 7", "test",
                pidFile.path,
            ],
            timeout: 5)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(result.status == 7)
        #expect(String(data: result.standardError, encoding: .utf8) == "parent failure")
        expectReaped(try #require(runner.processIdentifier))
    }
}
