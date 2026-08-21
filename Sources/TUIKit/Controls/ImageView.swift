import Foundation

/// Images — real pixels on a VectorTerminal, an honest card everywhere else.
///
/// ```text
///   cells:                          VTG:
///   ┌──────────────────────┐        (the picture, fitted in the bounds)
///   │ 🖼 logo.png           │
///   │   640×480 · PNG       │
///   └──────────────────────┘
/// ```
///
/// The cell form is the **placeholder + menu** pattern: a framed card with
/// the name, dimensions and format, and a context menu — Open in Viewer,
/// Copy (the path, or the name), Paste (replace the image from a path on
/// the pasteboard) — so the control stays *usable* over SSH. On a
/// VectorTerminal the pixels draw, fitted or filled, with the same menu.
///
/// ```swift
/// let logo = ImageView(data: pngData, caption: "logo.png")
/// logo.scaling = .fit
/// ```
@MainActor
public final class ImageView: TUIView {
    /// How the picture meets the bounds.
    public enum Scaling: Hashable, Sendable {
        /// Whole picture visible, letterboxed.
        case fit

        /// Bounds covered, picture cropped.
        case fill

        /// Stretched to the bounds.
        case stretch
    }

    /// PNG or JPEG bytes; `nil` shows an empty card.
    public private(set) var data: Data?

    /// The format of `data`, detected from its header.
    public private(set) var format: ChromeCommand.ImageFormat?

    /// Pixel size read from the header, when the header is one we read.
    public private(set) var pixelSize: (width: Int, height: Int)?

    /// Caption shown on the card (a file name, typically).
    public var caption: String {
        didSet {
            setNeedsDisplay()
        }
    }

    /// File the image came from, when it did — what Copy puts on the
    /// pasteboard, and what Open in Viewer passes on.
    public var path: String?

    /// How the picture meets the bounds.
    public var scaling: Scaling = .fit {
        didSet {
            setNeedsDisplay()
        }
    }

    /// Called when the context menu's Open in Viewer runs. The default
    /// presents an `ImageViewer` window in the app.
    public var onOpenInViewer: (() -> Void)?

    /// Called after Paste replaced the image.
    public var onImageChanged: () -> Void = {}

    /// Creates an image view.
    ///
    /// - Parameters:
    ///   - data: PNG or JPEG bytes.
    ///   - caption: Caption for the card.
    public init(data: Data? = nil, caption: String = "") {
        self.caption = caption
        super.init(frame: .zero)
        setData(data)
        contextMenu = makeMenu()
    }

    /// An image view over a file.
    ///
    /// - Parameter path: PNG or JPEG file.
    public convenience init(path: String) {
        self.init(data: FileManager.default.contents(atPath: path), caption: (path as NSString).lastPathComponent)
        self.path = path
    }

    /// A card's worth of cells; the picture itself scales to whatever it gets.
    public override var intrinsicContentSize: Size? {
        Size(width: max(24, caption.count + 6), height: 4)
    }

    /// Replaces the image.
    ///
    /// - Parameter newData: PNG or JPEG bytes, or `nil`.
    public func setData(_ newData: Data?) {
        data = newData
        format = newData.flatMap(Self.detectFormat)
        pixelSize = newData.flatMap(Self.readPixelSize)
        setNeedsDisplay()
    }

    /// The pixels on a VectorTerminal, the card everywhere else.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme

        if let data, let format, let chrome = painter.chrome, chrome.covers(bounds),
           bounds.size.width >= 2, bounds.size.height >= 1 {
            painter.withBase(CellStyle()).fill(bounds, with: .blank)
            chrome.image("pixels", placement(in: ChromeRect(bounds)), data: data, format: format)
            return
        }

        painter.fill(bounds, with: .blank)
        drawCard(painter, theme: theme)
    }

    // MARK: - Card

    private func drawCard(_ painter: Painter, theme: ResolvedTheme) {
        let width = bounds.size.width
        let height = bounds.size.height

        guard width >= 4, height >= 1 else {
            return
        }

        if height >= 3 {
            painter.drawBox(bounds, style: theme.border, border: theme.borderStyle.inner)
        }

        let inner = max(0, width - 4)
        let title = Label.truncated(data == nil ? "no image" : (caption.isEmpty ? "image" : caption), width: inner)
        painter.write("🖼 " + title, at: Point(x: 1, y: min(1, height - 1)), style: theme.base)

        if height >= 4 {
            painter.write(Label.truncated(detailLine, width: inner), at: Point(x: 3, y: 2), style: theme.placeholder)
        }
    }

    /// "640×480 · PNG", or what is known.
    public var detailLine: String {
        var parts: [String] = []

        if let pixelSize {
            parts.append("\(pixelSize.width)×\(pixelSize.height)")
        }

        if let format {
            parts.append(format == .png ? "PNG" : "JPEG")
        }

        if let data {
            parts.append("\(data.count) bytes")
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Menu

    private func makeMenu() -> Menu {
        let menu = Menu("")

        menu.addItem("Open in Viewer") { [weak self] in
            self?.openInViewer()
        }

        menu.addItem("Copy") { [weak self] in
            guard let self else { return }
            self.owningWindow?.app?.pasteboard.copy(self.path ?? self.caption)
        }

        menu.addItem("Paste") { [weak self] in
            guard let self, let text = self.owningWindow?.app?.pasteboard.string else { return }
            self.paste(text)
        }

        return menu
    }

    /// Opens the viewer, exactly as the menu does.
    public func openInViewer() {
        if let onOpenInViewer {
            onOpenInViewer()
            return
        }

        guard let app = owningWindow?.app else {
            return
        }

        let viewer = ImageViewer(image: self, frame: Rect(x: 4, y: 2, width: 60, height: 20))
        viewer.onCloseRequest = { [weak viewer, weak app] in
            if let viewer, let app {
                app.dismiss(viewer)
            }
        }
        app.present(viewer)
    }

    /// Replaces the image from a pasteboard string — a file path.
    ///
    /// - Parameter text: The pasted text.
    public func paste(_ text: String) {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let bytes = FileManager.default.contents(atPath: candidate),
              Self.detectFormat(bytes) != nil else {
            return
        }

        path = candidate
        caption = (candidate as NSString).lastPathComponent
        setData(bytes)
        onImageChanged()
    }

    // MARK: - Geometry

    func placement(in rect: ChromeRect) -> ChromeRect {
        guard let pixelSize, pixelSize.width > 0, pixelSize.height > 0, scaling != .stretch else {
            return rect
        }

        // Cells are about twice as tall as wide: aspect in cell units.
        let aspect = Double(pixelSize.width) / Double(pixelSize.height) / 2
        let byWidth = (width: rect.width, height: rect.width / aspect)
        let byHeight = (width: rect.height * aspect, height: rect.height)
        let chosen = scaling == .fit
            ? (byWidth.height <= rect.height ? byWidth : byHeight)
            : (byWidth.height >= rect.height ? byWidth : byHeight)

        return ChromeRect(
            x: rect.x + (rect.width - chosen.width) / 2,
            y: rect.y + (rect.height - chosen.height) / 2,
            width: chosen.width,
            height: chosen.height
        )
    }

    // MARK: - Headers

    static func detectFormat(_ data: Data) -> ChromeCommand.ImageFormat? {
        let bytes = [UInt8](data.prefix(4))

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .png
        }

        if bytes.starts(with: [0xFF, 0xD8]) {
            return .jpeg
        }

        return nil
    }

    static func readPixelSize(_ data: Data) -> (width: Int, height: Int)? {
        let bytes = [UInt8](data)

        switch detectFormat(data) {
        case .png:
            guard bytes.count >= 24 else { return nil }
            let width = bytes[16...19].reduce(0) { $0 << 8 | Int($1) }
            let height = bytes[20...23].reduce(0) { $0 << 8 | Int($1) }
            return (width, height)

        case .jpeg:
            // Walk the markers to the first SOF (C0–C3).
            var index = 2
            while index + 9 < bytes.count, bytes[index] == 0xFF {
                let marker = bytes[index + 1]
                let length = Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])

                if (0xC0...0xC3).contains(marker) {
                    let height = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
                    let width = Int(bytes[index + 7]) << 8 | Int(bytes[index + 8])
                    return (width, height)
                }

                index += 2 + length
            }
            return nil

        default:
            return nil
        }
    }
}

/// A zoomable, pannable image window — the `ImageView`'s Open in Viewer.
///
/// On a VectorTerminal `+`/`-` zoom and the arrows pan the pixels; on a
/// plain terminal the window shows the card, because the card is what the
/// terminal can show. Esc closes.
@MainActor
public final class ImageViewer: FloatingWindow {
    /// The image shown.
    public let image: ImageView

    /// Zoom factor; 1 fits.
    public private(set) var zoom = 1.0

    /// Pan offset in cells.
    public private(set) var pan = Point(x: 0, y: 0)

    /// Creates a viewer over an image view's data.
    ///
    /// - Parameters:
    ///   - image: Source image view (its data is shared).
    ///   - frame: Window frame.
    public init(image source: ImageView, frame: Rect) {
        image = ImageView(data: source.data, caption: source.caption)
        image.path = source.path
        super.init(title: source.caption.isEmpty ? "Image" : source.caption, frame: frame)
        image.anchors = .fill()
        image.scaling = .fit
        content.addSubview(image)
        image.onOpenInViewer = {}   // already here
    }

    /// `+`/`-` zoom, arrows pan, Esc closes.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return super.keyDown(key)
        }

        switch key.key {
        case .character("+"), .character("="):
            zoom = min(8, zoom * 1.25)
        case .character("-"):
            zoom = max(0.25, zoom / 1.25)
        case .left:
            pan = Point(x: pan.x - 2, y: pan.y)
        case .right:
            pan = Point(x: pan.x + 2, y: pan.y)
        case .up:
            pan = Point(x: pan.x, y: pan.y - 1)
        case .down:
            pan = Point(x: pan.x, y: pan.y + 1)
        case .escape:
            onCloseRequest()
            return true
        default:
            return super.keyDown(key)
        }

        image.setNeedsDisplay()
        return true
    }
}
