#!/usr/bin/env bash
# Generate every icon asset from Support/Icon/portscope-mark.svg.
#
# The app icon needs 10 sizes in an .icns; the menu bar needs a monochrome
# template image that macOS tints to match the menu bar. Both are derived from
# the same two SVGs, so the mark can never drift between them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT/Support/Icon"
OUT="$ICON_DIR/build"
WORK="$OUT/iconset.iconset"
RENDERER="$OUT/render"

mkdir -p "$OUT"
rm -rf "$WORK" "$OUT/AppIcon.icns" "$OUT/MenuBarIcon.png" "$OUT/MenuBarIcon@2x.png"

# --- renderer --------------------------------------------------------------
# A tiny WKWebView snapshotter, so no ImageMagick or librsvg is needed.
if [[ ! -x "$RENDERER" ]]; then
    echo "==> Building the SVG renderer"
    cat > "$OUT/render.swift" <<'SWIFT'
import AppKit
import WebKit

// Rasterise an SVG to a PNG of an exact pixel size.
//
// The SVG is loaded as an <img> with explicit width/height inside a body sized
// to match, and the *view* is snapshotted at 1x. Rendering the SVG markup
// inline instead let WebKit lay it out at its intrinsic 1024 and crop, which
// produced a corner-clipped icon.
let args = CommandLine.arguments
guard args.count >= 4 else { print("usage: render <svg> <out.png> <size>"); exit(2) }
let svgPath = args[1], outPath = args[2], size = Int(args[3]) ?? 1024

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Inline the SVG as a data URI: WebKit refuses to load a file:// image from
// an HTML string with no base URL, which silently produced a broken-image icon.
let svg = try! String(contentsOfFile: svgPath, encoding: .utf8)
let encoded = svg.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
let html = """
<html><head><style>
  html, body { margin: 0; padding: 0; background: transparent; }
  img { display: block; width: \(size)px; height: \(size)px; }
</style></head>
<body><img src="data:image/svg+xml;charset=utf-8,\(encoded)"></body></html>
"""

let view = WKWebView(
    frame: NSRect(x: 0, y: 0, width: size, height: size),
    configuration: WKWebViewConfiguration()
)
// Render at 1x so one CSS pixel is one output pixel.
view.wantsLayer = true
view.loadHTMLString(html, baseURL: URL(fileURLWithPath: svgPath).deletingLastPathComponent())

DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    let config = WKSnapshotConfiguration()
    config.rect = NSRect(x: 0, y: 0, width: size, height: size)
    config.snapshotWidth = NSNumber(value: size)
    view.takeSnapshot(with: config) { image, error in
        guard let image, let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else {
            FileHandle.standardError.write(Data("snapshot failed: \(String(describing: error))\n".utf8))
            exit(1)
        }
        // WebKit hands back a snapshot at the display's backing scale (2x on
        // this Mac) whatever `snapshotWidth` asks for. Redraw into a bitmap of
        // exactly `size` pixels so the .iconset names match their contents.
        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = target.representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: outPath))
        exit(0)
    }
}
app.run()
SWIFT
    swiftc -O "$OUT/render.swift" -o "$RENDERER"
fi

render() { "$RENDERER" "$1" "$2" "$3" >/dev/null; }

# --- app icon --------------------------------------------------------------
# macOS reads these exact names from an .iconset. Sizes below 64 px are drawn
# from the 64 px master and downsampled, because the arcs need to stay crisp.
echo "==> App icon"
mkdir -p "$WORK"
for size in 16 32 128 256 512; do
    render "$ICON_DIR/portscope-mark.svg" "$WORK/icon_${size}x${size}.png" "$size"
    double=$((size * 2))
    render "$ICON_DIR/portscope-mark.svg" "$WORK/icon_${size}x${size}@2x.png" "$double"
done
iconutil -c icns "$WORK" -o "$OUT/AppIcon.icns"
echo "    $OUT/AppIcon.icns"

# --- menu bar --------------------------------------------------------------
# Drawn with AppKit rather than rendered from SVG. A template image must be
# pure black on a *transparent* background; the WKWebView rasteriser composites
# onto an opaque white page, so the tinted template came out as a solid white
# square in the menu bar. Core Graphics draws the arcs with real alpha.
echo "==> Menu bar template"
cat > "$OUT/menubar.swift" <<'SWIFT'
import AppKit

// Draws the menu bar mark at one size. Geometry mirrors portscope-mark.svg on
// a 1024 grid, scaled so the mark fills a 24pt status item with breathing room.
func drawMenuBarIcon(size: CGFloat, to path: String) {
    let scale = size / 1024.0
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()
    NSColor.black.setStroke()

    // Geometry is authored on a 1024 grid; scale it into the target canvas.
    let centre = CGPoint(x: 512 * scale, y: 512 * scale)
    func ring(_ radius: CGFloat, _ width: CGFloat) {
        let path = NSBezierPath(
            ovalIn: NSRect(
                x: centre.x - radius * scale, y: centre.y - radius * scale,
                width: radius * 2 * scale, height: radius * 2 * scale
            )
        )
        path.lineWidth = width * scale
        path.stroke()
    }
    func arcs(_ radius: CGFloat, _ width: CGFloat, _ span: CGFloat) {
        for mid in [CGFloat(0), 180] {
            let path = NSBezierPath()
            path.appendArc(
                withCenter: centre, radius: radius * scale,
                startAngle: mid - span / 2, endAngle: mid + span / 2
            )
            path.lineWidth = width * scale
            path.lineCapStyle = .round
            path.stroke()
        }
    }

    ring(140, 76)
    arcs(250, 58, 116)
    arcs(350, 46, 100)

    image.unlockFocus()

    // Flatten to a bitmap with an alpha channel and write it.
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { exit(1) }
    rep.size = NSSize(width: size, height: size)
    guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
drawMenuBarIcon(size: 18, to: out + "/MenuBarIcon.png")
drawMenuBarIcon(size: 36, to: out + "/MenuBarIcon@2x.png")
SWIFT
swiftc -O "$OUT/menubar.swift" -o "$OUT/menubar"
"$OUT/menubar" "$OUT"
echo "    $OUT/MenuBarIcon.png, $OUT/MenuBarIcon@2x.png"

echo "==> Done"
