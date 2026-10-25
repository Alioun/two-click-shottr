import AppKit
import Testing

@testable import TwoClickShottr

@MainActor
struct CaptureVerificationTests {
    private func inspect(_ bitmap: NSBitmapImageRep, fixture: CaptureFixture) throws -> [String: Any] {
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            "capture-fixture-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        try data.write(to: file)
        return try Verification.inspect(file, fixture: fixture)
    }

    private func crop(_ fixture: CaptureFixture, rect: CGRect? = nil) throws -> NSBitmapImageRep {
        let image = try #require(try fixture.raster().cropping(to: rect ?? fixture.cropPixels))
        return NSBitmapImageRep(cgImage: image)
    }

    @Test func oddVisibleFramesKeepAnIntegralOriginAndExactSelectionSize() {
        for visibleFrame in [
            CGRect(x: 0, y: 25, width: 1511, height: 971),
            CGRect(x: -1511, y: -971, width: 1511, height: 971),
        ] {
            let frame = CaptureFixture.windowFrame(in: visibleFrame)
            #expect(frame.origin.x == floor(frame.origin.x))
            #expect(frame.origin.y == floor(frame.origin.y))
            #expect(frame.size == CGSize(width: 280, height: 220))
            let selected = CaptureFixture.selection.offsetBy(dx: frame.minX, dy: frame.minY)
            let quartz = CaptureGeometry.quartzRect(selected, primaryTop: 1080)
            #expect(quartz.size == CGSize(width: 160, height: 100))
            #expect(quartz.minX == selected.minX)
            #expect(quartz.minY == 1080 - selected.maxY)
        }
    }

    @Test func exactCropPassesAtStandardAndRetinaScales() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            let report = try inspect(crop(fixture), fixture: fixture)
            #expect(report["width"] as? Int == Int(160 * scale))
            #expect(report["height"] as? Int == Int(100 * scale))
            #expect(report["checkedPixels"] as? Int == Int(160 * scale) * Int(100 * scale))
            #expect(report["mismatches"] as? Int == 0)
            #expect(report["cropOriginVerified"] as? Bool == true)
            #expect(fixture.cropPixels.origin == CGPoint(x: 40 * scale, y: 80 * scale))
        }
    }

    @Test func productionFixtureViewDrawsTheExpectedRasterWithoutAWindow() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            let view = try CaptureFixtureView(fixture: fixture)
            let bitmap = NSBitmapImageRep(cgImage: try fixture.raster())
            bitmap.size = CaptureFixture.size
            let bytes = try #require(bitmap.bitmapData)
            bytes.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let rendered = try #require(bitmap.cgImage?.cropping(to: fixture.cropPixels))
            let report = try inspect(NSBitmapImageRep(cgImage: rendered), fixture: fixture)
            #expect(report["mismatches"] as? Int == 0)
        }
    }

    @Test func displacedCropsFailEvenWhenDimensionsMatch() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            for offset: CGFloat in [-20, -1, 1, 20] {
                for translation in [CGPoint(x: offset * scale, y: 0), CGPoint(x: 0, y: offset * scale)] {
                    let rect = fixture.cropPixels.offsetBy(dx: translation.x, dy: translation.y)
                    let displaced = try crop(fixture, rect: rect)
                    #expect(throws: CaptureFailure.self) { try inspect(displaced, fixture: fixture) }
                }
            }
            let swappedOrigin = fixture.cropPixels.offsetBy(dx: 40 * scale, dy: -40 * scale)
            let displaced = try crop(fixture, rect: swappedOrigin)
            #expect(throws: CaptureFailure.self) { try inspect(displaced, fixture: fixture) }
        }
    }

    @Test func mirroredAndSwappedPixelsFailAtUnchangedDimensions() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            let original = try crop(fixture)
            for transform in 0..<3 {
                let changed = try crop(fixture)
                var components = [Int](repeating: 0, count: original.samplesPerPixel)
                for y in 0..<original.pixelsHigh {
                    for x in 0..<original.pixelsWide {
                        let source: (Int, Int)
                        switch transform {
                        case 0: source = (original.pixelsWide - 1 - x, y)
                        case 1: source = (x, original.pixelsHigh - 1 - y)
                        default:
                            source = (
                                y * original.pixelsWide / original.pixelsHigh,
                                x * original.pixelsHigh / original.pixelsWide
                            )
                        }
                        original.getPixel(&components, atX: source.0, y: source.1)
                        changed.setPixel(&components, atX: x, y: y)
                    }
                }
                #expect(throws: CaptureFailure.self) { try inspect(changed, fixture: fixture) }
            }
        }
    }

    @Test func wrongDimensionsFailIncludingTransposedDimensions() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            let correct = fixture.cropPixels
            let sizes = [
                CGSize(width: correct.width - 1, height: correct.height),
                CGSize(width: correct.width, height: correct.height - 1),
                CGSize(width: correct.width + 1, height: correct.height),
                CGSize(width: correct.width, height: correct.height + 1),
                CGSize(width: correct.height, height: correct.width),
            ]
            for size in sizes {
                let changed = try crop(fixture, rect: CGRect(origin: .zero, size: size))
                #expect(throws: CaptureFailure.self) { try inspect(changed, fixture: fixture) }
            }
        }
    }

    @Test func overlayBorderAndDimmedPixelsFail() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            let border = try crop(fixture)
            var yellow = [Int](repeating: 255, count: border.samplesPerPixel)
            yellow[2] = 0
            border.setPixel(&yellow, atX: 0, y: 0)
            #expect(throws: CaptureFailure.self) { try inspect(border, fixture: fixture) }

            let dimmed = try crop(fixture)
            var components = [Int](repeating: 0, count: dimmed.samplesPerPixel)
            for y in 0..<dimmed.pixelsHigh {
                for x in 0..<dimmed.pixelsWide {
                    dimmed.getPixel(&components, atX: x, y: y)
                    for channel in 0..<3 { components[channel] = Int(CGFloat(components[channel]) * 0.78) }
                    dimmed.setPixel(&components, atX: x, y: y)
                }
            }
            #expect(throws: CaptureFailure.self) { try inspect(dimmed, fixture: fixture) }
        }
    }

    @Test func profileConversionAndSmallRoundingErrorsRemainAccepted() throws {
        for scale: CGFloat in [1, 2] {
            let fixture = CaptureFixture(scale: scale)
            let original = try crop(fixture)
            let p3 = try #require(original.converting(to: .displayP3, renderingIntent: .default))
            let report = try inspect(p3, fixture: fixture)
            #expect(report["mismatches"] as? Int == 0)

            var components = [Int](repeating: 0, count: original.samplesPerPixel)
            for y in 0..<original.pixelsHigh {
                for x in 0..<original.pixelsWide {
                    original.getPixel(&components, atX: x, y: y)
                    for channel in 0..<3 { components[channel] += 2 }
                    original.setPixel(&components, atX: x, y: y)
                }
            }
            let roundedReport = try inspect(original, fixture: fixture)
            #expect(roundedReport["mismatches"] as? Int == 0)
        }
    }

    @Test func flatColorCannotStandInForCoordinateEvidence() throws {
        let fixture = CaptureFixture(scale: 2)
        let bitmap = try crop(fixture)
        var color = [51, 153, 217, 255]
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide { bitmap.setPixel(&color, atX: x, y: y) }
        }
        #expect(throws: CaptureFailure.self) { try inspect(bitmap, fixture: fixture) }
    }
}
