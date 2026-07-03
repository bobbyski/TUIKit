/// Horizontal placement of text within a control.
public enum TextAlignment: Hashable, Sendable {
    /// Text starts at the leading edge.
    case leading

    /// Text centers in the available width.
    case center

    /// Text ends at the trailing edge.
    case trailing
}

/// Single-line text display.
///
/// Labels are the simplest control: they show text, truncate with an
/// ellipsis when space runs out, and report their natural size so layout
/// containers can fit them.
///
/// ```swift
/// let title = Label("Report", style: CellStyle(flags: .bold))
/// ```
@MainActor
public final class Label: View {
    /// Text shown by the label.
    public var text: String {
        didSet {
            if text != oldValue {
                superview?.setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    /// Style applied to the text.
    public var style: CellStyle {
        didSet {
            if style != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Horizontal placement of the text.
    public var alignment: TextAlignment {
        didSet {
            if alignment != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Creates a label.
    ///
    /// - Parameters:
    ///   - text: Text to show.
    ///   - style: Style applied to the text.
    ///   - alignment: Horizontal placement of the text.
    public init(
        _ text: String,
        style: CellStyle = .default,
        alignment: TextAlignment = .leading
    ) {
        self.text = text
        self.style = style
        self.alignment = alignment
        super.init(frame: .zero)
    }

    /// One row at the text's character count.
    public override var intrinsicContentSize: Size? {
        Size(width: text.count, height: 1)
    }

    /// Draws the text, aligned and truncated to the bounds.
    public override func draw(_ painter: Painter) {
        let width = bounds.size.width

        guard width > 0, bounds.size.height > 0 else {
            return
        }

        let visible = Self.truncated(text, width: width)
        let x: Int

        switch alignment {
        case .leading:
            x = 0
        case .center:
            x = (width - visible.count) / 2
        case .trailing:
            x = width - visible.count
        }

        painter.write(visible, at: Point(x: x, y: 0), style: style)
    }

    /// Truncates text to a width, ending with an ellipsis when cut.
    ///
    /// - Parameters:
    ///   - text: Text to truncate.
    ///   - width: Available cell count.
    /// - Returns: The text, or a prefix ending in `…` when it does not fit.
    static func truncated(_ text: String, width: Int) -> String {
        guard text.count > width else {
            return text
        }

        guard width > 1 else {
            return width == 1 ? "…" : ""
        }

        return String(text.prefix(width - 1)) + "…"
    }
}
