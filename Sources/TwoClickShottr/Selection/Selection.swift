import Foundation

enum SelectionMode: String, CaseIterable {
    case twoClick
    case drag

    var title: String { self == .twoClick ? "Two clicks" : "Drag" }
}

enum SelectionEvent {
    case down(CGPoint)
    case move(CGPoint)
    case up(CGPoint)
    case cancel
}

enum SelectionState: Equatable {
    case waiting
    case firstPressed(anchor: CGPoint, current: CGPoint)
    case betweenClicks(anchor: CGPoint, current: CGPoint)
    case secondPressed(anchor: CGPoint, current: CGPoint)
    case dragging(anchor: CGPoint, current: CGPoint)
    case completed(CGRect)
    case cancelled

    var preview: CGRect? {
        switch self {
        case .firstPressed(let a, let p), .betweenClicks(let a, let p),
            .secondPressed(let a, let p), .dragging(let a, let p):
            return CaptureGeometry.rectangle(a, p)
        case .completed(let rect): return rect
        case .waiting, .cancelled: return nil
        }
    }

    mutating func receive(_ event: SelectionEvent, mode: SelectionMode) {
        switch self {
        case .completed, .cancelled: return
        default: break
        }
        if case .cancel = event {
            self = .cancelled
            return
        }
        switch (self, event) {
        case (.waiting, .down(let p)):
            self = mode == .twoClick ? .firstPressed(anchor: p, current: p) : .dragging(anchor: p, current: p)
        case (.firstPressed(let a, _), .move(let p)):
            self = .firstPressed(anchor: a, current: p)
        case (.firstPressed(let a, _), .up(let p)):
            self = .betweenClicks(anchor: a, current: p)
        case (.betweenClicks(let a, _), .move(let p)):
            self = .betweenClicks(anchor: a, current: p)
        case (.betweenClicks(let a, _), .down(let p)):
            self = .secondPressed(anchor: a, current: p)
        case (.secondPressed(let a, _), .move(let p)):
            self = .secondPressed(anchor: a, current: p)
        case (.secondPressed(let a, _), .up(let p)):
            let rect = CaptureGeometry.rectangle(a, p)
            self =
                rect.width > 0 && rect.height > 0 ? .completed(rect) : .betweenClicks(anchor: a, current: p)
        case (.dragging(let a, _), .move(let p)):
            self = .dragging(anchor: a, current: p)
        case (.dragging(let a, _), .up(let p)):
            let rect = CaptureGeometry.rectangle(a, p)
            self = rect.width > 0 && rect.height > 0 ? .completed(rect) : .waiting
        default: break
        }
    }
}

enum CaptureGeometry {
    static func rectangle(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func quartzRect(_ rect: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryTop - rect.maxY, width: rect.width, height: rect.height).integral
    }

    static func argument(_ rect: CGRect) -> String {
        [rect.minX, rect.minY, rect.width, rect.height].map { String(Int($0)) }.joined(separator: ",")
    }
}
