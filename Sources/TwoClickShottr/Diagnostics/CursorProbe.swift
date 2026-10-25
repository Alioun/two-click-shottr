import AppKit

@MainActor
struct CursorProbe {
    let cursor = NSCursor.currentSystem
    let applicationActive = NSApp.isActive
    let expected: NSCursor

    var matchesCrosshair: Bool {
        cursor?.hotSpot == expected.hotSpot
            && cursor?.image.tiffRepresentation == expected.image.tiffRepresentation
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
