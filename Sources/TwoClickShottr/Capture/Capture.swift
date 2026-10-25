import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum CaptureService {
    static let compositorDelayNanoseconds: UInt64 = 200_000_000

    static var backendName: String {
        if #available(macOS 14.0, *) { return "ScreenCaptureKit filtered screenshot" }
        return "screencapture compatibility backend"
    }

    static func capture(
        _ quartzRect: CGRect, runner: ProcessRunner? = nil,
        expectedDisplays: [CGDirectDisplayID: CGRect]? = nil,
        exceptingWindows: Set<CGWindowID> = []
    ) async throws -> URL {
        try Task.checkCancellation()
        if #available(macOS 14.0, *) {
            return try await captureNative(
                quartzRect, expectedDisplays: expectedDisplays,
                exceptingWindows: exceptingWindows)
        }
        return try await captureLegacy(quartzRect, runner: runner ?? ProcessRunner())
    }

    private static func captureLegacy(_ quartzRect: CGRect, runner: ProcessRunner) async throws -> URL {
        // Window-server composition is asynchronous after orderOut. The live verifier checks this delay.
        try await Task.sleep(nanoseconds: compositorDelayNanoseconds)
        let file = try CaptureFiles.makeURL()
        let result: ProcessRunner.Result
        do {
            result = try await runner.run(
                executable: URL(fileURLWithPath: "/usr/sbin/screencapture"),
                arguments: ["-x", "-t", "png", "-R", CaptureGeometry.argument(quartzRect), file.path],
                timeout: 30)
        } catch is CancellationError {
            throw CancellationError()
        } catch ProcessRunner.Failure.timedOut {
            throw CaptureFailure(
                message: "screencapture timed out. Any partial image remains at \(file.path)",
                stage: .acquisition)
        } catch {
            throw CaptureFailure(
                message:
                    "Could not start screencapture. \(error.localizedDescription)\nCapture path: \(file.path)",
                stage: .acquisition)
        }
        try Task.checkCancellation()
        guard result.reason == .exit, result.status == 0, FileManager.default.fileExists(atPath: file.path)
        else {
            if !CGPreflightScreenCaptureAccess() {
                throw CaptureFailure(
                    message: "Screen Recording permission is required. Allow this app in System Settings.",
                    kind: .screenRecordingDenied, stage: .acquisition)
            }
            let detail =
                String(data: result.standardError, encoding: .utf8)?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
            throw CaptureFailure(
                message:
                    "screencapture failed with status \(result.status). \(detail)\nAny partial image remains at \(file.path)",
                stage: .acquisition)
        }
        return file
    }

    @available(macOS 14.0, *)
    private static func captureNative(
        _ rectangle: CGRect, expectedDisplays: [CGDirectDisplayID: CGRect]?,
        exceptingWindows: Set<CGWindowID>
    ) async throws -> URL {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch { throw CaptureFailure.native(error, stage: .discovery) }
        try Task.checkCancellation()
        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        guard !ownApplications.isEmpty else {
            throw CaptureFailure(
                message: "Could not exclude the companion's windows from capture.", stage: .discovery)
        }
        let bounds = Dictionary(
            uniqueKeysWithValues: content.displays.map { ($0.displayID, CGDisplayBounds($0.displayID)) })
        try validateDisplays(expectedDisplays, actual: bounds)
        let plan = try CapturePlan(selection: rectangle, displays: bounds)
        let exceptions = content.windows.filter { exceptingWindows.contains($0.windowID) }
        var images: [(CapturePlan.Tile, CGImage)] = []
        for tile in plan.tiles {
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == tile.displayID }) else {
                throw CaptureFailure(
                    message: "The selected display is no longer available.", stage: .geometry)
            }
            let filter = SCContentFilter(
                display: display, excludingApplications: ownApplications, exceptingWindows: exceptions)
            let scale = plan.tiles.count == 1 ? CGFloat(filter.pointPixelScale) : 1
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = tile.source
            configuration.width = Int((tile.source.width * scale).rounded(.up))
            configuration.height = Int((tile.source.height * scale).rounded(.up))
            configuration.preservesAspectRatio = false
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            if #available(macOS 15.0, *) { configuration.captureMicrophone = false }
            let image: CGImage
            do {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration)
            } catch { throw CaptureFailure.native(error, stage: .acquisition) }
            try Task.checkCancellation()
            guard image.width == configuration.width, image.height == configuration.height else {
                throw CaptureFailure(
                    message: "Capture returned unexpected pixel dimensions.", stage: .acquisition)
            }
            images.append((tile, image))
        }
        let currentBounds = Dictionary(
            uniqueKeysWithValues: content.displays.map { ($0.displayID, CGDisplayBounds($0.displayID)) })
        try validateDisplays(bounds, actual: currentBounds)
        let image: CGImage
        if images.count == 1 { image = images[0].1 } else { image = try plan.compose(images) }
        try Task.checkCancellation()
        return try writePNG(image)
    }

    private static func validateDisplays(
        _ expected: [CGDirectDisplayID: CGRect]?,
        actual: [CGDirectDisplayID: CGRect]
    ) throws {
        if let expected, expected != actual {
            throw CaptureFailure(message: "Display layout changed. Start a new capture.", stage: .geometry)
        }
    }

    private static func writePNG(_ image: CGImage) throws -> URL {
        do {
            let file = try CaptureFiles.makeURL()
            guard
                let destination = CGImageDestinationCreateWithURL(
                    file as CFURL, UTType.png.identifier as CFString, 1, nil)
            else {
                throw CaptureFailure(message: "Could not create PNG at \(file.path)", stage: .encoding)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw CaptureFailure(message: "Could not finish PNG at \(file.path)", stage: .encoding)
            }
            return file
        } catch let failure as CaptureFailure { throw failure } catch {
            throw CaptureFailure(
                message: "Could not save the screenshot. \(error.localizedDescription)", stage: .encoding)
        }
    }

    @MainActor
    static func openInShottr(_ file: URL) async throws {
        try Task.checkCancellation()
        let workspace = NSWorkspace.shared
        guard let app = workspace.urlForApplication(withBundleIdentifier: AppIdentity.shottrBundleIdentifier),
            Bundle(url: app)?.bundleIdentifier == AppIdentity.shottrBundleIdentifier
        else {
            throw CaptureFailure(
                message:
                    "Shottr could not be found. Install Shottr, then open the saved image at \(file.path)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await workspace.open([file], withApplicationAt: app, configuration: configuration)
        } catch {
            throw CaptureFailure(
                message:
                    "Shottr could not open the image. \(error.localizedDescription)\nThe image remains at \(file.path)"
            )
        }
    }
}
