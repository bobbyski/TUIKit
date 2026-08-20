import Foundation
import TUIKit

// Headless snapshot mode: renders every gallery tab to an SVG (cells AND
// vector chrome) without a terminal.
//
//   TUIKIT_GALLERY_SNAPSHOT=/tmp/gallery swift run TUIKitGallery
//
// Exists for eyeballing layout changes (this is how the gallery itself was
// reviewed while being built) and for docs screenshots — the SVG is drawn
// from the same CellBuffer + ChromeCommand output a terminal would receive.

/// Renders each tab into `directory` as `tab-N-Title.svg`. Returns after
/// writing; the caller exits instead of running the app.
@MainActor
func writeGallerySnapshots(to directory: String) throws {
    let size = Size(width: 110, height: 32)
    let app = App(driver: HeadlessDriver(size: size))
    app.applyTheme(.modernTurbo)
    app.desktop.frame = Rect(origin: .zero, size: size)
    app.desktop.fillStyle = CellStyle(background: Theme.modernTurbo.resolved(for: .desktop).background)

    let window = makeGalleryWindow(index: 0, app: app)
    window.frame = Rect(x: 2, y: 1, width: size.width - 4, height: size.height - 2)
    app.present(window)

    guard let tabs = firstTabView(in: window) else {
        return
    }

    let renderer = SceneRenderer(root: app.desktop)
    renderer.chromeEnabled = true

    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    for index in 0..<tabs.tabCount {
        tabs.select(index)
        let buffer = renderer.render(size: size)
        let svg = gallerySVG(buffer: buffer, chrome: renderer.chromeCommands, size: size)
        let name = "tab-\(index)-\(tabs.title(at: index) ?? "tab").svg"
        try svg.write(toFile: (directory as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
        print("wrote \(directory)/\(name)")
    }
}

@MainActor
private func firstTabView(in view: TUIView) -> TabView? {
    if let tabs = view as? TabView {
        return tabs
    }

    for subview in view.subviews {
        if let found = firstTabView(in: subview) {
            return found
        }
    }

    return nil
}

// MARK: - SVG assembly (cells + chrome, same fidelity as a terminal)

@MainActor
private func gallerySVG(buffer: CellBuffer, chrome: [ChromeCommand], size: Size) -> String {
    let cw = 9.0, ch = 18.0
    var svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="\(Double(size.width) * cw)" height="\(Double(size.height) * ch)" font-family="Menlo, monospace" font-size="13">
    <rect width="100%" height="100%" fill="#1a1a1a"/>
    """

    func css(_ color: ChromeColor) -> String {
        "rgba(\(color.red),\(color.green),\(color.blue),\(Double(color.alpha) / 255))"
    }

    func cellCSS(_ color: TerminalColor, fallback: String) -> String {
        // The public cell→chrome conversion doubles as the RGB lookup.
        guard let rgb = ChromeColor(color) else {
            return fallback
        }

        return "rgb(\(rgb.red),\(rgb.green),\(rgb.blue))"
    }

    func roundedPath(_ rect: ChromeRect, radius: Double, corners: ChromeCorners) -> String {
        let x = rect.x * cw, y = rect.y * ch, w = rect.width * cw, h = rect.height * ch
        let rad = min(radius * ch, min(w, h) / 2)
        let tl = corners.contains(.topLeft) ? rad : 0
        let tr = corners.contains(.topRight) ? rad : 0
        let br = corners.contains(.bottomRight) ? rad : 0
        let bl = corners.contains(.bottomLeft) ? rad : 0
        return "M\(x + tl),\(y) H\(x + w - tr) A\(tr),\(tr) 0 0 1 \(x + w),\(y + tr) V\(y + h - br) "
            + "A\(br),\(br) 0 0 1 \(x + w - br),\(y + h) H\(x + bl) A\(bl),\(bl) 0 0 1 \(x),\(y + h - bl) "
            + "V\(y + tl) A\(tl),\(tl) 0 0 1 \(x + tl),\(y) Z"
    }

    for command in chrome {
        switch command.shape {
        case .rect(let rect, let fill, let stroke, let lineWidth, let radius, let corners):
            svg += "<path d=\"\(roundedPath(rect, radius: radius, corners: corners))\" fill=\"\(fill.map(css) ?? "none")\" stroke=\"\(stroke.map(css) ?? "none")\" stroke-width=\"\(max(1, lineWidth * ch))\"/>\n"

        case .circle(let center, let radius, let fill, let stroke, let lineWidth):
            svg += "<circle cx=\"\(center.x * cw)\" cy=\"\(center.y * ch)\" r=\"\(radius * ch)\" fill=\"\(fill.map(css) ?? "none")\" stroke=\"\(stroke.map(css) ?? "none")\" stroke-width=\"\(max(1, lineWidth * ch))\"/>\n"

        case .line(let from, let to, let color, let width):
            svg += "<line x1=\"\(from.x * cw)\" y1=\"\(from.y * ch)\" x2=\"\(to.x * cw)\" y2=\"\(to.y * ch)\" stroke=\"\(css(color))\" stroke-width=\"\(max(1, width * ch))\"/>\n"

        case .polyline(let points, let color, let width):
            let list = points.map { "\($0.x * cw),\($0.y * ch)" }.joined(separator: " ")
            svg += "<polyline points=\"\(list)\" fill=\"none\" stroke=\"\(css(color))\" stroke-width=\"\(max(1, width * ch))\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>\n"

        case .polygon(let points, let fill, let stroke, let width):
            let list = points.map { "\($0.x * cw),\($0.y * ch)" }.joined(separator: " ")
            svg += "<polygon points=\"\(list)\" fill=\"\(fill.map(css) ?? "none")\" stroke=\"\(stroke.map(css) ?? "none")\" stroke-width=\"\(max(1, width * ch))\"/>\n"

        case .sector(let center, let radius, let innerRadius, let start, let end, let fill):
            // Chart angles (0 = 12 o'clock, clockwise) into SVG arcs; the
            // pixel-space circle stays round at cell scale ch.
            func at(_ r: Double, _ angle: Double) -> (Double, Double) {
                (center.x * cw + r * ch * Foundation.sin(angle), center.y * ch - r * ch * Foundation.cos(angle))
            }

            let large = (end - start) > Double.pi ? 1 : 0
            let o0 = at(radius, start), o1 = at(radius, end)
            var d = "M \(o0.0) \(o0.1) A \(radius * ch) \(radius * ch) 0 \(large) 1 \(o1.0) \(o1.1)"

            if innerRadius > 0 {
                let i1 = at(innerRadius, end), i0 = at(innerRadius, start)
                d += " L \(i1.0) \(i1.1) A \(innerRadius * ch) \(innerRadius * ch) 0 \(large) 0 \(i0.0) \(i0.1)"
            } else {
                d += " L \(center.x * cw) \(center.y * ch)"
            }

            svg += "<path d=\"\(d) Z\" fill=\"\(css(fill))\"/>\n"

        case .image, .sprite:
            break   // raster payloads don't belong in a text snapshot
        }
    }

    for y in 0..<size.height {
        for x in 0..<size.width {
            let cell = buffer[Point(x: x, y: y)]

            if cell.style.background != .standard {
                svg += "<rect x=\"\(Double(x) * cw)\" y=\"\(Double(y) * ch)\" width=\"\(cw)\" height=\"\(ch)\" fill=\"\(cellCSS(cell.style.background, fallback: "#000"))\"/>\n"
            }

            if cell.character != " " {
                let weight = cell.style.flags.contains(.bold) ? " font-weight=\"bold\"" : ""
                let glyph = String(cell.character)
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                svg += "<text x=\"\(Double(x) * cw + cw / 2)\" y=\"\(Double(y) * ch + ch - 4)\" text-anchor=\"middle\" fill=\"\(cellCSS(cell.style.foreground, fallback: "#ccc"))\"\(weight)>\(glyph)</text>\n"
            }
        }
    }

    return svg + "</svg>"
}
