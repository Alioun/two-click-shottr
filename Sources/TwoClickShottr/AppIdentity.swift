import Foundation

enum AppIdentity {
    static let bundleIdentifier = "local.two-click-shottr"
    static let shottrBundleIdentifier = "cc.ffitch.shottr"
}

enum CaptureFiles {
    static func makeURL() throws -> URL {
        let manager = FileManager.default
        let caches = try manager.url(
            for: .cachesDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let directory = caches.appendingPathComponent(AppIdentity.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("Captures", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Capture-\(UUID().uuidString).png")
    }
}
