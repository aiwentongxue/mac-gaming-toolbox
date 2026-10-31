#!/usr/bin/env swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Export the ImageGen artwork into a standard macOS canvas. The geometric
// clipping is part of asset packaging: it removes alpha flecks outside the tile.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = project.appendingPathComponent("Artwork/AppIcon-generated.png")
let iconSet = project.appendingPathComponent("Sources/MacGameToolbox/Assets.xcassets/LegacyAppIcon.appiconset")
let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let edge = CGFloat(min(artwork.width, artwork.height))
let crop = CGRect(x: edge * 0.078, y: edge * 0.078, width: edge * 0.844, height: edge * 0.844)
let tileArtwork = artwork.cropping(to: crop)!
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}
let masterContext = context(1024, 1024)
let tile = CGRect(x: 51.2, y: 51.2, width: 921.6, height: 921.6)
masterContext.addPath(CGPath(roundedRect: tile, cornerWidth: tile.width * 0.24, cornerHeight: tile.height * 0.24, transform: nil))
masterContext.clip()
masterContext.interpolationQuality = .high
masterContext.draw(tileArtwork, in: tile)
let master = masterContext.makeImage()!
write(master, to: project.appendingPathComponent("Artwork/AppIcon-master.png"))
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: iconSet.appendingPathComponent("Contents.json"))) as! [String: Any]
for item in manifest["images"] as! [[String: String]] {
    let points = Int(item["size"]!.split(separator: "x")[0])!
    let scale = item["scale"] == "2x" ? 2 : 1
    let size = points * scale
    let bitmap = context(size, size)
    bitmap.interpolationQuality = .high
    bitmap.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    write(bitmap.makeImage()!, to: iconSet.appendingPathComponent(item["filename"]!))
}
print("Exported AppIcon master and all 10 macOS icon slots")

// Native Icon Composer foreground uses a full 1024 canvas. The enclosure and
// opaque gradient belong to icon.json, not to this transparent foreground.
let controllerSource = CGImageSourceCreateWithURL(project.appendingPathComponent("Artwork/Controller-generated.png") as CFURL, nil)!
let controller = CGImageSourceCreateImageAtIndex(controllerSource, 0, nil)!
let foreground = context(1024, 1024)
foreground.interpolationQuality = .high
foreground.draw(controller, in: CGRect(x: 112.64, y: 112.64, width: 798.72, height: 798.72))
write(foreground.makeImage()!, to: project.appendingPathComponent("Sources/MacGameToolbox/AppIcon.icon/Assets/controller.png"))
print("Exported native Icon Composer foreground")
