import Testing

@testable import TwoClickShottr

struct LaunchModeTests {
    @Test func ordinaryLaunchIgnoresUnknownArguments() {
        #expect(LaunchMode(arguments: ["TwoClickShottr"]) == .application)
        #expect(LaunchMode(arguments: ["TwoClickShottr", "--unknown"]) == .application)
    }

    @Test func diagnosticFlagsKeepTheirEstablishedPrecedence() {
        #expect(LaunchMode(arguments: ["--verify-capture", "--diagnose"]) == .diagnose)
        #expect(
            LaunchMode(arguments: ["--verify-selection", "--verify-exclusive-hotkey"]) == .exclusiveHotKey)
    }

    @Test func observationOnlyWorkloadsPreventImageCapture() {
        #expect(LaunchMode.triggerLatency.preventsCapture)
        #expect(LaunchMode.resourceProfile.preventsCapture)
        #expect(!LaunchMode.application.preventsCapture)
        #expect(!LaunchMode.capture.preventsCapture)
    }
}
