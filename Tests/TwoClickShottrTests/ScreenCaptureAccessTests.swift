import Foundation
import Testing

@testable import TwoClickShottr

private final class PermissionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let release = DispatchSemaphore(value: 0)
    var calls: Int { lock.withLock { count } }

    func check() -> Bool {
        lock.withLock { count += 1 }
        release.wait()
        return true
    }
}

@MainActor
struct ScreenCaptureAccessTests {
    @Test func permissionCheckRunsOffTheMainThreadAndCachesItsResult() async {
        let access = ScreenCaptureAccess(check: { !Thread.isMainThread })
        #expect(access.cached == nil)
        #expect(await access.refresh())
        #expect(access.cached == true)
    }

    @Test func concurrentRefreshesShareOneCheckAndCannotUndoADenial() async throws {
        let probe = PermissionProbe()
        let access = ScreenCaptureAccess(check: { probe.check() })
        let first = Task { await access.refresh() }
        var secondEntered = false
        let second = Task {
            secondEntered = true
            return await access.refresh()
        }
        defer { for _ in 0..<4 { probe.release.signal() } }
        let deadline = Date(timeIntervalSinceNow: 1)
        while probe.calls == 0 && Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        while !secondEntered { await Task.yield() }
        #expect(probe.calls == 1)
        access.record(false)
        probe.release.signal()
        #expect(await first.value == false)
        #expect(await second.value == false)
        #expect(access.cached == false)
        probe.release.signal()
        #expect(await access.refresh())
        #expect(access.cached == true)
    }
}
