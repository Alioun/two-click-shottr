import AppKit

struct CaptureFixture {
    static let size = CGSize(width: 280, height: 220)
    static let selection = CGRect(x: 40, y: 40, width: 160, height: 100)
    let scale: CGFloat

    static func windowFrame(in visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: floor(visibleFrame.midX - size.width / 2),
            y: floor(visibleFrame.midY - size.height / 2), width: size.width, height: size.height)
    }

    var pixelWidth: Int { Int((Self.size.width * scale).rounded()) }
    var pixelHeight: Int { Int((Self.size.height * scale).rounded()) }
    var cropPixels: CGRect {
        CGRect(
            x: Self.selection.minX * scale,
            y: (Self.size.height - Self.selection.maxY) * scale,
            width: Self.selection.width * scale, height: Self.selection.height * scale)
    }

    func color(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let column = UInt32(floor(CGFloat(x) / (4 * scale)))
        let row = UInt32(floor(CGFloat(y) / (4 * scale)))
        var marker = column &* 73_856_093 ^ row &* 19_349_663 ^ 0x9e37_79b9
        marker = (marker ^ (marker >> 16)) &* 0x85eb_ca6b
        marker = (marker ^ (marker >> 13)) &* 0xc2b2_ae35
        marker ^= marker >> 16
        return (
            UInt8(32 + 64 * (marker & 3)),
            UInt8(32 + 64 * ((marker >> 2) & 3)),
            UInt8(32 + 64 * ((marker >> 4) & 3))
        )
    }

    func raster() throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: pixelWidth * pixelHeight * 4)
        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let pixel = color(x: x, y: y)
                let offset = (y * pixelWidth + x) * 4
                bytes[offset] = pixel.red
                bytes[offset + 1] = pixel.green
                bytes[offset + 2] = pixel.blue
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(bytes) as CFData),
            let image = CGImage(
                width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: pixelWidth * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            throw CaptureFailure(message: "The coordinate fixture could not be rasterized.")
        }
        return image
    }
}

@MainActor
final class CaptureFixtureView: NSView {
    private let image: NSImage
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    init(fixture: CaptureFixture) throws {
        image = NSImage(cgImage: try fixture.raster(), size: CaptureFixture.size)
        super.init(frame: NSRect(origin: .zero, size: CaptureFixture.size))
    }

    required init?(coder: NSCoder) { return nil }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(
            in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }
}
