import AppKit
import Testing

@testable import TwoClickShottr

@MainActor
struct OverlayRenderingTests {
    private func pixel(in view: SelectionView, at point: CGPoint, scale: Int) throws -> [UInt8] {
        view.displayIfNeeded()
        for subview in view.subviews { subview.displayIfNeeded() }
        let width = Int(view.bounds.width) * scale
        let height = Int(view.bounds.height) * scale
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        try #require(view.layer).render(in: context)
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let offset = ((height - 1 - Int(point.y) * scale) * width + Int(point.x) * scale) * 4
        return Array(UnsafeBufferPointer(start: bytes + offset, count: 4))
    }

    @Test func dimmingHoleAndOutlineStayCorrectAcrossUpdatesAndScales() throws {
        for scale in [1, 2] {
            let selection = SelectionController(mode: .twoClick) { _ in }
            selection.start(frames: [CGRect(x: 0, y: 0, width: 400, height: 300)], visible: false)
            defer { selection.hide() }
            let view = try #require(selection.windows[0].contentView as? SelectionView)
            let anchor = CGPoint(x: 100, y: 100)
            selection.receive(.down(anchor))
            selection.receive(.up(anchor))
            selection.receive(.move(CGPoint(x: 300, y: 220)))
            #expect(try pixel(in: view, at: CGPoint(x: 200, y: 150), scale: scale)[3] == 0)
            let dim = try pixel(in: view, at: CGPoint(x: 50, y: 50), scale: scale)
            #expect(abs(Int(dim[3]) - 56) <= 1)
            #expect(dim[0] == 0 && dim[1] == 0 && dim[2] == 0)
            #expect(try pixel(in: view, at: CGPoint(x: 100, y: 150), scale: scale)[3] == 255)

            selection.receive(.move(CGPoint(x: 50, y: 50)))
            #expect(try pixel(in: view, at: CGPoint(x: 90, y: 60), scale: scale)[3] == 0)
            #expect(abs(Int(try pixel(in: view, at: CGPoint(x: 200, y: 150), scale: scale)[3]) - 56) <= 1)

            selection.receive(.move(anchor))
            #expect(abs(Int(try pixel(in: view, at: CGPoint(x: 90, y: 60), scale: scale)[3]) - 56) <= 1)
        }
    }

    @Test func repeatedPointerPositionLeavesLayerContentsAlone() throws {
        let selection = SelectionController(mode: .twoClick) { _ in }
        selection.start(frames: [CGRect(x: -400, y: 0, width: 400, height: 300)], visible: false)
        defer { selection.hide() }
        selection.receive(.move(CGPoint(x: -200, y: 150)))
        let view = try #require(selection.windows[0].contentView as? SelectionView)
        let shade = try #require(view.layer?.sublayers?.first as? CAShapeLayer)
        let path = try #require(shade.path)
        selection.receive(.move(CGPoint(x: -200, y: 150)))
        #expect(shade.path === path)
    }
}
