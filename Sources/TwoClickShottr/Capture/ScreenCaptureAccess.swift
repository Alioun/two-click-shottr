import CoreGraphics

@MainActor
final class ScreenCaptureAccess {
    private(set) var cached: Bool?
    private let check: @Sendable () -> Bool
    private var pending: Task<Bool, Never>?
    private var revision: UInt64 = 0

    init(check: @escaping @Sendable () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.check = check
    }

    func refresh() async -> Bool {
        if pending == nil {
            revision &+= 1
            pending = Task.detached(priority: .userInitiated, operation: check)
        }
        let currentRevision = revision
        let task = pending!
        let allowed = await task.value
        guard revision == currentRevision else { return cached ?? false }
        cached = allowed
        pending = nil
        return allowed
    }

    func record(_ allowed: Bool) {
        revision &+= 1
        cached = allowed
        pending = nil
    }
}
