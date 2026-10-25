import Foundation

enum LaunchMode: String, CaseIterable {
    case exclusiveHotKey = "--verify-exclusive-hotkey"
    case hotKeyConflictChild = "--verify-hotkey-conflict-child"
    case hotKeyFreeChild = "--verify-hotkey-free-child"
    case diagnose = "--diagnose"
    case selection = "--verify-selection"
    case cursor = "--verify-cursor"
    case capture = "--verify-capture"
    case triggerLatency = "--verify-trigger-latency"
    case resourceProfile = "--profile-resources"
    case application = ""

    init(arguments: [String] = CommandLine.arguments) {
        self = Self.allCases.first { !$0.rawValue.isEmpty && arguments.contains($0.rawValue) } ?? .application
    }

    var preventsCapture: Bool { self == .triggerLatency || self == .resourceProfile }
}
