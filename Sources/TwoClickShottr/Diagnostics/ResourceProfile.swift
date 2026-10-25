import AppKit
import Darwin

@MainActor
enum ResourceProfile {
    private struct Sample {
        let time = ProcessInfo.processInfo.systemUptime
        let usage: rusage

        init() {
            var value = rusage()
            getrusage(RUSAGE_SELF, &value)
            usage = value
        }

        func report(since start: Sample) -> [String: Any] {
            func seconds(_ value: timeval) -> Double {
                Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
            }
            return [
                "elapsedSeconds": time - start.time,
                "cpuSeconds": seconds(usage.ru_utime) + seconds(usage.ru_stime)
                    - seconds(start.usage.ru_utime) - seconds(start.usage.ru_stime),
                "voluntaryContextSwitches": usage.ru_nvcsw - start.usage.ru_nvcsw,
                "peakResidentBytes": usage.ru_maxrss,
            ]
        }
    }

    static func run(selection preparedSelection: SelectionController? = nil) async -> Never {
        let previousApp = NSWorkspace.shared.frontmostApplication
        try? await Task.sleep(nanoseconds: 500_000_000)
        let idleStart = Sample()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let idle = Sample().report(since: idleStart)
        let selection = preparedSelection ?? SelectionController(mode: .twoClick) { _ in }
        selection.start(mode: .twoClick)
        for _ in 0..<40 {
            if NSApp.isActive { break }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        guard let window = selection.windows.first, NSApp.isActive else {
            selection.receive(.cancel)
            Verification.finish(
                ["passed": false, "error": "Selector could not become active."], success: false)
        }
        window.contentView?.displayIfNeeded()
        let stationaryStart = Sample()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let stationary = Sample().report(since: stationaryStart)
        let frame = window.frame.insetBy(dx: 40, dy: 40)
        let anchor = CGPoint(x: frame.minX, y: frame.minY)
        Verification.inject(.leftMouseDown, at: anchor, into: window)
        Verification.inject(.leftMouseUp, at: anchor, into: window)
        let count = 240
        var endpoint = anchor
        let movementStart = Sample()
        for index in 0..<count {
            let progress = CGFloat(index) / CGFloat(count - 1)
            endpoint = CGPoint(
                x: frame.minX + frame.width * (0.5 + progress * 0.5),
                y: frame.minY + frame.height * (0.5 + progress * 0.5))
            Verification.inject(.mouseMoved, at: endpoint, into: window)
            for window in selection.windows { window.contentView?.displayIfNeeded() }
            try? await Task.sleep(nanoseconds: 8_333_333)
        }
        let movement = Sample().report(since: movementStart)
        let correct = selection.state.preview == CaptureGeometry.rectangle(anchor, endpoint)
        let displays = selection.windows.map {
            [
                "width": $0.frame.width, "height": $0.frame.height,
                "scale": $0.backingScaleFactor,
            ]
        }
        selection.receive(.cancel)
        previousApp?.activate(options: [])
        Verification.finish(
            [
                "passed": correct, "idle": idle, "stationarySelection": stationary,
                "movingSelection": movement, "movementEvents": count, "displays": displays,
                "measurement":
                    "getrusage process CPU and peak RSS. Production event handlers and visible displayIfNeeded rendering. No capture or global input.",
            ], success: correct)
    }
}
