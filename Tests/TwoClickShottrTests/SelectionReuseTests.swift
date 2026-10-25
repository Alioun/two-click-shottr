import AppKit
import Testing

@testable import TwoClickShottr

@MainActor
struct SelectionReuseTests {
    @Test func preparedWindowsRestartWithFreshSelectionAndChangedMode() throws {
        var results: [CGRect?] = []
        let selector = SelectionController(mode: .twoClick, reuseWindows: true) { results.append($0) }
        defer {
            selector.hide()
            selector.discardPreparedWindows()
        }
        let frames = [CGRect(x: -400, y: 0, width: 400, height: 300)]
        selector.prepare(frames: frames)
        #expect(selector.windows.isEmpty)
        selector.start(frames: frames, visible: false)
        let window = try #require(selector.windows.first)
        selector.receive(.down(CGPoint(x: -350, y: 20)))
        selector.receive(.up(CGPoint(x: -350, y: 20)))
        selector.receive(.cancel)
        #expect(results.count == 1 && results[0] == nil)
        #expect((window.contentView as? SelectionView)?.selection == nil)

        selector.start(frames: frames, visible: false, mode: .drag)
        #expect(selector.windows.first === window)
        #expect(selector.state == .waiting)
        selector.receive(.down(CGPoint(x: -300, y: 100)))
        selector.receive(.up(CGPoint(x: -100, y: 200)))
        #expect(results.count == 2)
        #expect(results[1] == CGRect(x: -300, y: 100, width: 200, height: 100))
        #expect(selector.windows.isEmpty)
    }

    @Test func changedDisplayLayoutReplacesPreparedWindows() throws {
        let selector = SelectionController(mode: .twoClick, reuseWindows: true) { _ in }
        defer {
            selector.hide()
            selector.discardPreparedWindows()
        }
        selector.start(frames: [CGRect(x: 0, y: 0, width: 400, height: 300)], visible: false)
        let original = try #require(selector.windows.first)
        selector.receive(.cancel)
        let replacement = CGRect(x: -500, y: -200, width: 500, height: 400)
        selector.start(frames: [replacement], visible: false)
        #expect(selector.windows.first !== original)
        #expect(selector.windows.first?.frame == replacement)
        #expect((original.contentView as? SelectionView)?.selection == nil)
    }
}
