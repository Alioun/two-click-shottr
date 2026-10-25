import CoreGraphics

struct CapturePlan {
    struct Tile: Equatable {
        let displayID: CGDirectDisplayID
        let source: CGRect
        let destination: CGRect
    }

    let selection: CGRect
    let tiles: [Tile]

    init(selection: CGRect, displays: [CGDirectDisplayID: CGRect]) throws {
        guard !selection.isNull, !selection.isInfinite,
            selection.origin.x.isFinite, selection.origin.y.isFinite,
            selection.width > 0, selection.height > 0,
            selection.width < CGFloat(Int32.max), selection.height < CGFloat(Int32.max)
        else {
            throw CaptureFailure(message: "The selected rectangle is invalid.", stage: .geometry)
        }
        let selection = selection.integral
        self.selection = selection
        tiles = displays.sorted { $0.key < $1.key }.compactMap { id, bounds in
            let intersection = selection.intersection(bounds)
            guard !intersection.isNull, !intersection.isEmpty else { return nil }
            return Tile(
                displayID: id,
                source: intersection.offsetBy(dx: -bounds.minX, dy: -bounds.minY),
                destination: intersection.offsetBy(dx: -selection.minX, dy: -selection.minY))
        }
        guard !tiles.isEmpty else {
            throw CaptureFailure(
                message: "The selected rectangle does not intersect a display.", stage: .geometry)
        }
    }

    func compose(_ images: [(Tile, CGImage)]) throws -> CGImage {
        guard
            let context = CGContext(
                data: nil, width: Int(selection.width), height: Int(selection.height),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw CaptureFailure(message: "Could not allocate the screenshot image.", stage: .acquisition)
        }
        context.interpolationQuality = .none
        for (tile, image) in images {
            let destination = tile.destination
            context.draw(
                image,
                in: CGRect(
                    x: destination.minX, y: selection.height - destination.maxY,
                    width: destination.width, height: destination.height))
        }
        guard let image = context.makeImage() else {
            throw CaptureFailure(message: "Could not compose the screenshot image.", stage: .acquisition)
        }
        return image
    }
}
