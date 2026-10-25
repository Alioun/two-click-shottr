import CoreGraphics
import Foundation
import ScreenCaptureKit
import Testing

@testable import TwoClickShottr

struct NativeCaptureTests {
    @Test func denialChecksBothNativeDomainAndCodeAndNeverNeedsAGenericAlert() throws {
        let denied = try #require(
            CaptureFailure.native(
                NSError(
                    domain: SCStreamErrorDomain,
                    code: SCStreamError.Code.userDeclined.rawValue), stage: .discovery) as? CaptureFailure)
        #expect(denied.kind == .screenRecordingDenied)
        #expect(denied.isCaptureFailure)
        #expect(denied.underlying?.domain == SCStreamErrorDomain)
        let unrelated = try #require(
            CaptureFailure.native(
                NSError(domain: "Other", code: -3801),
                stage: .acquisition) as? CaptureFailure)
        #expect(unrelated.kind == .general)
        #expect(unrelated.isCaptureFailure)
        #expect(unrelated.underlying?.domain == "Other")
        let wrapped = NSError(
            domain: "Wrapper", code: 1,
            userInfo: [NSUnderlyingErrorKey: denied.underlying!])
        let wrappedDenial = try #require(CaptureFailure.native(wrapped, stage: .discovery) as? CaptureFailure)
        #expect(wrappedDenial.kind == .screenRecordingDenied)
        #expect(wrappedDenial.underlying?.domain == "Wrapper")
    }

    @Test func userStoppedAndTaskCancellationStayQuietWhileEncodingAndHandoffStayActionable() {
        #expect(
            CaptureFailure.native(
                NSError(
                    domain: SCStreamErrorDomain,
                    code: SCStreamError.Code.userStopped.rawValue), stage: .acquisition) is CancellationError)
        #expect(CaptureFailure.native(CancellationError(), stage: .discovery) is CancellationError)
        #expect(!CaptureFailure(message: "disk full", stage: .encoding).isCaptureFailure)
        #expect(!CaptureFailure(message: "Shottr absent").isCaptureFailure)
    }

    @Test func negativeOriginsAndVerticalArrangementRemainInDisplayLocalPoints() throws {
        let plan = try CapturePlan(
            selection: CGRect(x: -30, y: -20, width: 80, height: 70),
            displays: [
                1: CGRect(x: -100, y: -100, width: 100, height: 200),
                2: CGRect(x: 0, y: 0, width: 100, height: 100),
            ])
        #expect(
            plan.tiles == [
                CapturePlan.Tile(
                    displayID: 1, source: CGRect(x: 70, y: 80, width: 30, height: 70),
                    destination: CGRect(x: 0, y: 0, width: 30, height: 70)),
                CapturePlan.Tile(
                    displayID: 2, source: CGRect(x: 0, y: 0, width: 50, height: 50),
                    destination: CGRect(x: 30, y: 20, width: 50, height: 50)),
            ])
    }

    @Test func invalidAndOffDesktopSelectionsFailBeforeCapture() {
        let displays: [CGDirectDisplayID: CGRect] = [1: CGRect(x: 0, y: 0, width: 100, height: 100)]
        for rect in [
            CGRect.zero, CGRect.null, CGRect.infinite,
            CGRect(x: 200, y: 200, width: 10, height: 10),
        ] {
            #expect(throws: CaptureFailure.self) { try CapturePlan(selection: rect, displays: displays) }
        }
    }

    @Test func compositionUsesOnePixelPerPointAndPreservesOrientationAndTransparentGaps() throws {
        let plan = try CapturePlan(
            selection: CGRect(x: -2, y: -2, width: 6, height: 4),
            displays: [
                1: CGRect(x: -2, y: -2, width: 2, height: 2),
                2: CGRect(x: 2, y: 0, width: 2, height: 2),
            ])
        func tileImage(red: CGFloat, green: CGFloat) throws -> CGImage {
            let context = try #require(
                CGContext(
                    data: nil, width: 2, height: 2, bitsPerComponent: 8,
                    bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(red: red, green: green, blue: 0, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            return try #require(context.makeImage())
        }
        let result = try plan.compose([
            (plan.tiles[0], tileImage(red: 1, green: 0)),
            (plan.tiles[1], tileImage(red: 0, green: 1)),
        ])
        #expect(result.width == 6 && result.height == 4)
        let data = try #require(result.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        func rgba(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = y * result.bytesPerRow + x * 4
            return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
        }
        #expect(rgba(0, 0) == [255, 0, 0, 255])
        #expect(rgba(4, 2) == [0, 255, 0, 255])
        #expect(rgba(2, 1) == [0, 0, 0, 0])
        #expect(rgba(0, 3) == [0, 0, 0, 0])
    }
}
