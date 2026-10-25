// Lays out the DMG window in Finder, or reads the saved layout back from a mounted image.
// Usage: swift dmg-layout.swift apply|check VOLUME
import AppKit

let appName = "Two Click Shottr.app"
let windowSize = NSSize(width: 560, height: 340)
let iconSize = 128.0
let iconY = 150.0
let appX = 150.0
let applicationsX = 410.0
let background = ".background/background.tiff"

let arguments = CommandLine.arguments
guard arguments.count == 3, ["apply", "check"].contains(arguments[1]) else {
    FileHandle.standardError.write(Data("Usage: dmg-layout.swift apply|check VOLUME\n".utf8))
    exit(1)
}
let volume = URL(fileURLWithPath: arguments[2], isDirectory: true)
let backgroundURL = volume.appendingPathComponent(background)

// Finder positions use a top-left origin; AppKit draws from the bottom left.
func drawBackground() {
    NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1).setFill()
    NSRect(origin: .zero, size: windowSize).fill()

    let arrowStyle = NSImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.6, alpha: 1)]))
    let arrow = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)!
        .withSymbolConfiguration(arrowStyle)!
    arrow.draw(
        in: NSRect(
            x: (appX + applicationsX - arrow.size.width) / 2,
            y: windowSize.height - iconY - arrow.size.height / 2,
            width: arrow.size.width, height: arrow.size.height))

    let centered = NSMutableParagraphStyle()
    centered.alignment = .center
    let caption = NSAttributedString(
        string: "Drag Two Click Shottr to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(white: 0.42, alpha: 1),
            .paragraphStyle: centered,
        ])
    let captionHeight = caption.size().height
    let captionY = iconY + iconSize / 2 + 62
    caption.draw(
        in: NSRect(
            x: 0, y: windowSize.height - captionY - captionHeight / 2,
            width: windowSize.width, height: captionHeight))
}

func render(scale: Double) -> NSBitmapImageRep {
    let image = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(windowSize.width * scale),
        pixelsHigh: Int(windowSize.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    image.size = windowSize
    return image
}

// Every Finder reference goes through the volume alias. Disk names can collide with a mounted release.
func finder(_ body: String) -> String {
    let script = """
        on run {volumePath, backgroundPath}
            set dmg to POSIX file volumePath as alias
            set backgroundFile to POSIX file backgroundPath as alias
            tell application "Finder"
                with timeout of 120 seconds
        \(body)
                end timeout
            end tell
        end run
        """
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script, volume.path, backgroundURL.path]
    process.standardOutput = output
    try! process.run()
    let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    if process.terminationStatus != 0 { exit(process.terminationStatus) }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

if arguments[1] == "check" {
    // Finder fails to read back background picture (-10000), so packaging checks the rest.
    let expected =
        "icon view, \(Int(iconSize)), \(Int(appX)), \(Int(iconY)), \(Int(applicationsX)), \(Int(iconY))"
    let saved = finder(
        """
        return {current view of container window of item dmg as text, ¬
            icon size of icon view options of container window of item dmg, ¬
            position of item "\(appName)" of item dmg, position of item "Applications" of item dmg}
        """)
    guard saved == expected else {
        FileHandle.standardError.write(Data("Finder layout is \(saved); expected \(expected).\n".utf8))
        exit(1)
    }
    exit(0)
}

try FileManager.default.createDirectory(
    at: backgroundURL.deletingLastPathComponent(), withIntermediateDirectories: false)
try NSBitmapImageRep.tiffRepresentationOfImageReps(
    in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
    .write(to: backgroundURL)
_ = finder(
    """
    open dmg
    tell container window of item dmg
        set current view to icon view
        set toolbar visible to false
        set statusbar visible to false
        set pathbar visible to false
        set bounds to {200, 120, \(200 + Int(windowSize.width)), \(120 + Int(windowSize.height))}
    end tell
    tell icon view options of container window of item dmg
        set arrangement to not arranged
        set icon size to \(Int(iconSize))
        set text size to 13
        set label position to bottom
        set shows item info to false
        set shows icon preview to false
        set background picture to backgroundFile
    end tell
    set position of item "\(appName)" of item dmg to {\(Int(appX)), \(Int(iconY))}
    set position of item "Applications" of item dmg to {\(Int(applicationsX)), \(Int(iconY))}
    close container window of item dmg
    open dmg
    update item dmg without registering applications
    delay 1
    close container window of item dmg
    """)
