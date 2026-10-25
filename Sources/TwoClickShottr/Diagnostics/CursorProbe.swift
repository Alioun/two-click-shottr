import AppKit

@MainActor
struct CursorProbe {
    let cursor = NSCursor.currentSystem
    let applicationActive = NSApp.isActive
    private static let crosshair = NSCursor.crosshair

    var matchesCrosshair: Bool {
        cursor?.hotSpot == Self.crosshair.hotSpot
            && cursor?.image.tiffRepresentation == Self.crosshair.image.tiffRepresentation
    }

    static func waitForCrosshair() async -> CursorProbe {
        for _ in 0..<1000 {
            let sample = CursorProbe()
            if sample.applicationActive && sample.matchesCrosshair { return sample }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return CursorProbe()
    }
}
