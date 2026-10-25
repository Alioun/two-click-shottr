// Lays out the DMG window in Finder, or reads the saved layout back from a mounted image.
// Usage: swift dmg-layout.swift apply|check VOLUME
import AppKit

let appName = "Two Click Shottr.app"
let guideName = "Opening the app.rtf"
let windowSize = NSSize(width: 560, height: 520)
let iconSize: CGFloat = 128.0
let iconY: CGFloat = 150.0
let appX: CGFloat = 150.0
let applicationsX: CGFloat = 410.0
let guideX: CGFloat = 280.0
let guideY: CGFloat = 370.0
let background = ".background/background.tiff"
let appleGuide = URL(string: "https://support.apple.com/en-us/102445")!

let arguments = CommandLine.arguments
guard arguments.count == 3, ["apply", "check"].contains(arguments[1]) else {
    FileHandle.standardError.write(Data("Usage: dmg-layout.swift apply|check VOLUME\n".utf8))
    exit(1)
}
let volume = URL(fileURLWithPath: arguments[2], isDirectory: true)
let backgroundURL = volume.appendingPathComponent(background)
let guideURL = volume.appendingPathComponent(guideName)

func guideDocument() -> NSAttributedString {
    let body = NSFont.systemFont(ofSize: 13)
    let spaced = NSMutableParagraphStyle()
    spaced.paragraphSpacing = 8
    let document = NSMutableAttributedString()
    func add(_ text: String, _ attributes: [NSAttributedString.Key: Any] = [:]) {
        document.append(
            NSAttributedString(
                string: text, attributes: [.font: body, .paragraphStyle: spaced].merging(attributes) { $1 }))
    }
    add("Opening Two Click Shottr\n", [.font: NSFont.boldSystemFont(ofSize: 18)])
    add(
        "Two Click Shottr is an experimental app. Apple has not notarized it, so macOS may block it "
            + "the first time it opens. Continue only if you trust this download.\n")
    let steps = [
        "Drag Two Click Shottr to the Applications folder.",
        "Open Two Click Shottr from Applications.",
        "If macOS says it cannot check the app for malicious software, click Done.",
        "Open System Settings, click Privacy & Security, then scroll down.",
        "Click Open Anyway next to the message about Two Click Shottr.",
        "Click Open when the warning appears again. Enter your password if macOS asks.",
    ]
    for (number, step) in steps.enumerated() { add("\(number + 1). \(step)\n") }
    add("After that, the app opens from Applications like any other app.\n")
    add("Apple describes these steps in ")
    add("Safely open apps on your Mac", [.link: appleGuide])
    add(".\n")
    add("Screen Recording access is a separate request that comes after the app opens.\n")
    return document
}

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

func render(scale: CGFloat) -> NSBitmapImageRep {
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
        "icon view, \(Int(iconSize)), \(Int(appX)), \(Int(iconY)), \(Int(applicationsX)), \(Int(iconY)), "
        + "\(Int(guideX)), \(Int(guideY))"
    let saved = finder(
        """
        return {current view of container window of item dmg as text, ¬
            icon size of icon view options of container window of item dmg, ¬
            position of item "\(appName)" of item dmg, position of item "Applications" of item dmg, ¬
            position of item "\(guideName)" of item dmg}
        """)
    guard saved == expected else {
        FileHandle.standardError.write(Data("Finder layout is \(saved); expected \(expected).\n".utf8))
        exit(1)
    }
    let shipped = try NSAttributedString(
        url: guideURL, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
    let linkAt = (shipped.string as NSString).range(of: "Safely open apps").location
    guard shipped.string == guideDocument().string, linkAt != NSNotFound,
        shipped.attribute(.link, at: linkAt, effectiveRange: nil) as? URL == appleGuide
    else {
        FileHandle.standardError.write(Data("\(guideName) does not match the generated guide.\n".utf8))
        exit(1)
    }
    exit(0)
}

try FileManager.default.createDirectory(
    at: backgroundURL.deletingLastPathComponent(), withIntermediateDirectories: false)
try NSBitmapImageRep.tiffRepresentationOfImageReps(
    in: [render(scale: 1), render(scale: 2)], using: .lzw, factor: 0)!
    .write(to: backgroundURL)
let guide = guideDocument()
try guide.rtf(
    from: NSRange(location: 0, length: guide.length),
    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])!
    .write(to: guideURL)
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
    set position of item "\(guideName)" of item dmg to {\(Int(guideX)), \(Int(guideY))}
    close container window of item dmg
    open dmg
    update item dmg without registering applications
    delay 1
    close container window of item dmg
    """)
