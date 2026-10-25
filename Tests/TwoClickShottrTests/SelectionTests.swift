import Foundation
import Testing

@testable import TwoClickShottr

struct SelectionTests {
    private let a = CGPoint(x: 100, y: 200)
    private let b = CGPoint(x: 350, y: 500)

    @Test func testTwoClicksFinishOnlyOnSecondRelease() {
        var state = SelectionState.waiting
        state.receive(.down(a), mode: .twoClick)
        state.receive(.move(b), mode: .twoClick)
        #expect(state.preview == CGRect(x: 100, y: 200, width: 250, height: 300))
        state.receive(.up(a), mode: .twoClick)
        #expect(state == .betweenClicks(anchor: a, current: a))
        state.receive(.move(b), mode: .twoClick)
        state.receive(.down(b), mode: .twoClick)
        #expect(state == .secondPressed(anchor: a, current: b))
        let release = CGPoint(x: 360, y: 510)
        state.receive(.up(release), mode: .twoClick)
        #expect(state == .completed(CGRect(x: 100, y: 200, width: 260, height: 310)))
    }

    @Test func testFirstReleaseWithAreaDoesNotFinish() {
        var state = SelectionState.waiting
        state.receive(.down(a), mode: .twoClick)
        state.receive(.up(b), mode: .twoClick)
        #expect(state == .betweenClicks(anchor: a, current: b))
    }

    @Test func testReverseCornersNormalizeInBothModes() {
        for mode in SelectionMode.allCases {
            var state = SelectionState.waiting
            state.receive(.down(b), mode: mode)
            if mode == .twoClick {
                state.receive(.up(b), mode: mode)
                state.receive(.down(a), mode: mode)
            }
            state.receive(.up(a), mode: mode)
            #expect(state == .completed(CGRect(x: 100, y: 200, width: 250, height: 300)))
        }
    }

    @Test func testDragCommitsReleasePosition() {
        var state = SelectionState.waiting
        state.receive(.down(a), mode: .drag)
        state.receive(.move(CGPoint(x: 300, y: 400)), mode: .drag)
        #expect(state == .dragging(anchor: a, current: CGPoint(x: 300, y: 400)))
        state.receive(.up(b), mode: .drag)
        #expect(state == .completed(CGRect(x: 100, y: 200, width: 250, height: 300)))
    }

    @Test func testZeroAreaTwoClickKeepsAnchorAndRetries() {
        for zero in [a, CGPoint(x: a.x, y: b.y), CGPoint(x: b.x, y: a.y)] {
            var state = SelectionState.waiting
            state.receive(.down(a), mode: .twoClick)
            state.receive(.up(a), mode: .twoClick)
            state.receive(.down(zero), mode: .twoClick)
            state.receive(.up(zero), mode: .twoClick)
            #expect(state == .betweenClicks(anchor: a, current: zero))
            state.receive(.down(b), mode: .twoClick)
            state.receive(.up(b), mode: .twoClick)
            #expect(state == .completed(CaptureGeometry.rectangle(a, b)))
        }
    }

    @Test func testZeroDragRetriesWithNewAnchor() {
        var state = SelectionState.waiting
        state.receive(.down(a), mode: .drag)
        state.receive(.up(a), mode: .drag)
        #expect(state == .waiting)
        state.receive(.down(b), mode: .drag)
        state.receive(.up(a), mode: .drag)
        #expect(state == .completed(CaptureGeometry.rectangle(a, b)))
    }

    @Test func testCancelEveryActivePhaseIsTerminal() {
        let phases: [SelectionState] = [
            .waiting, .firstPressed(anchor: a, current: b),
            .betweenClicks(anchor: a, current: b), .secondPressed(anchor: a, current: b),
            .dragging(anchor: a, current: b),
        ]
        for var state in phases {
            state.receive(.cancel, mode: .twoClick)
            #expect(state == .cancelled)
            state.receive(.down(a), mode: .twoClick)
            state.receive(.up(b), mode: .twoClick)
            #expect(state == .cancelled)
        }
    }

    @Test func testCompletedSelectionCannotCommitAgain() {
        let result = SelectionState.completed(CaptureGeometry.rectangle(a, b))
        var state = result
        state.receive(.up(a), mode: .twoClick)
        state.receive(.cancel, mode: .twoClick)
        #expect(state == result)
    }

    @Test func testStrayReleaseAndMovementCannotStartSelection() {
        var state = SelectionState.waiting
        state.receive(.up(a), mode: .twoClick)
        state.receive(.move(b), mode: .twoClick)
        #expect(state == .waiting)
    }

    @Test func testQuartzGeometryRetainsNegativeOriginsWithoutScaling() {
        let appKit = CGRect(x: -1500, y: 900, width: 800, height: 600)
        let quartz = CaptureGeometry.quartzRect(appKit, primaryTop: 1080)
        #expect(quartz == CGRect(x: -1500, y: -420, width: 800, height: 600))
        #expect(CaptureGeometry.argument(quartz) == "-1500,-420,800,600")
    }

    @Test func testQuartzGeometryBelowPrimaryAndFractionalEdges() {
        let rect = CGRect(x: -10.4, y: -200.2, width: 100.1, height: 100.1)
        #expect(
            CaptureGeometry.quartzRect(rect, primaryTop: 900)
                == CGRect(x: -11, y: 1000, width: 101, height: 101))
    }
}
