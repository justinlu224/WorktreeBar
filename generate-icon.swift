#!/usr/bin/swift
import AppKit

// Generate WorktreeBar app icon from SF Symbol "arrow.triangle.branch"

let sizes: [(name: String, size: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let iconsetPath = "\(scriptDir)/AppIcon.iconset"
let icnsPath = "\(scriptDir)/AppIcon.icns"

let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for entry in sizes {
    let s = CGFloat(entry.size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    // Background: rounded rectangle with gradient
    let bounds = NSRect(x: 0, y: 0, width: s, height: s)
    let cornerRadius = s * 0.22
    let path = NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius)

    // Gradient from teal to dark blue
    let gradient = NSGradient(
        starting: NSColor(red: 0.15, green: 0.75, blue: 0.7, alpha: 1.0),
        ending: NSColor(red: 0.1, green: 0.3, blue: 0.55, alpha: 1.0)
    )!
    gradient.draw(in: path, angle: -45)

    // Draw SF Symbol tinted white
    let symbolPt = s * 0.55
    let config = NSImage.SymbolConfiguration(pointSize: symbolPt, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let symSize = symbol.size
        let x = (s - symSize.width) / 2
        let y = (s - symSize.height) / 2
        let drawRect = NSRect(x: x, y: y, width: symSize.width, height: symSize.height)

        // Tint symbol white using sourceAtop compositing
        let tinted = NSImage(size: symSize)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: symSize))
        NSColor.white.set()
        NSRect(origin: .zero, size: symSize).fill(using: .sourceAtop)
        tinted.unlockFocus()

        tinted.draw(in: drawRect)
    }

    image.unlockFocus()

    // Save as PNG
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render \(entry.name)")
    }
    try png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(entry.name).png"))
}

// Convert iconset to icns
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try process.run()
process.waitUntilExit()

// Cleanup iconset
try? fm.removeItem(atPath: iconsetPath)

if process.terminationStatus == 0 {
    print("Generated \(icnsPath)")
} else {
    fatalError("iconutil failed")
}
