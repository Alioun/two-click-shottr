import AppKit

@MainActor
struct CursorProbe {
    let cursor = NSCursor.currentSystem
    let applicationActive = NSApp.isActive
    let expected: NSCursor

    var matchesCrosshair: Bool {
        guard let cursor, cursor.hotSpot == expected.hotSpot else { return false }
        return Self.imagesMatch(cursor.image, expected.image)
    }

    static func imagesMatch(_ actual: NSImage, _ expected: NSImage) -> Bool {
        guard actual.size == expected.size,
            let actualPixels = pixels(actual), let expectedPixels = pixels(expected)
        else { return false }
        return actualPixels == expectedPixels
    }

    // TIFF representations can differ even when AppKit displays the same cursor.
    private static func pixels(_ image: NSImage) -> Data? {
        let width = Int(image.size.width * 2)
        let height = Int(image.size.height * 2)
        guard width > 0, height > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap), let data = bitmap.bitmapData
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.cgContext.clear(rect)
        image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
        return Data(bytes: data, count: width * height * 4)
    }

    static func waitForCursor(_ expected: NSCursor) async -> CursorProbe {
        for _ in 0..<1000 {
            let sample = CursorProbe(expected: expected)
            if sample.applicationActive && sample.matchesCrosshair { return sample }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return CursorProbe(expected: expected)
    }
}
