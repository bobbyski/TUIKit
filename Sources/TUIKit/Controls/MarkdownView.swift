/// Scrolling markdown reader.
///
/// Renders markdown through RichSwift `Markdown` (headings, lists, block
/// quotes, inline bold/code, fenced code blocks with syntax highlighting),
/// then soft-wraps the styled result to the view's width — RichSwift keeps
/// one output line per source line, so paragraph wrapping is this view's
/// job. Long documents scroll vertically: arrows, PageUp/PageDown,
/// Home/End while focused, the wheel anytime, with a proportional ░/█
/// indicator in the last column when the document overflows.
///
/// ```swift
/// let readme = MarkdownView(markdown: try String(contentsOfFile: path))
/// ```
///
/// Read-only by design; for editable text see `SyntaxTextView`.
@MainActor
public final class MarkdownView: View {
    /// The markdown source.
    public private(set) var markdown: String

    /// First visible wrapped row.
    public private(set) var scrollOffset = 0

    /// Creates a markdown view.
    ///
    /// - Parameter markdown: Markdown source text.
    public init(markdown: String = "") {
        self.markdown = markdown
        super.init(frame: .zero)
    }

    /// Replaces the document and scrolls back to the top.
    ///
    /// - Parameter markdown: New markdown source.
    public func setMarkdown(_ markdown: String) {
        self.markdown = markdown
        scrollOffset = 0
        cachedWidth = nil
        cachedLines = []
        setNeedsDisplay()
    }

    /// Markdown views take keyboard focus to own the scroll keys.
    public override var acceptsFirstResponder: Bool {
        true
    }

    /// Draws the visible wrapped slice and the overflow indicator.
    public override func draw(_ painter: Painter) {
        let height = bounds.size.height
        let width = bounds.size.width

        guard height > 0, width > 0 else {
            return
        }

        let lines = wrappedLines()
        scrollOffset = clampedOffset(scrollOffset)

        for row in 0..<height {
            let index = scrollOffset + row

            guard index < lines.count else {
                break
            }

            var x = 0

            for run in lines[index] {
                painter.write(run.text, at: Point(x: x, y: row), style: run.style)
                x += run.text.count
            }
        }

        // Proportional indicator when the document overflows: rounded
        // bar × (visible ÷ total), min 2 cells, never the whole bar.
        if lines.count > height {
            let proportional = (height * height + lines.count / 2) / lines.count
            let thumbLength = min(max(height > 2 ? 2 : 1, proportional), max(1, height - 1))
            let maxThumbStart = height - thumbLength
            let maxOffset = lines.count - height
            let thumbStart = maxOffset > 0 ? min(maxThumbStart, scrollOffset * maxThumbStart / maxOffset) : 0
            let (trackStyle, thumbStyle) = ScrollView.indicatorStyles(
                for: effectiveTheme,
                focused: isFirstResponder
            )

            for cell in 0..<height {
                let inThumb = cell >= thumbStart && cell < thumbStart + thumbLength
                painter.set(
                    TerminalCell(character: " ", style: inThumb ? thumbStyle : trackStyle),
                    at: Point(x: width - 1, y: cell)
                )
            }
        }
    }

    /// Scroll keys; consumed even at the edges.
    public override func keyDown(_ key: KeyInput) -> Bool {
        guard key.modifiers.isEmpty else {
            return false
        }

        let page = max(1, bounds.size.height - 1)

        switch key.key {
        case .up:
            scroll(by: -1)
            return true

        case .down:
            scroll(by: 1)
            return true

        case .pageUp:
            scroll(by: -page)
            return true

        case .pageDown:
            scroll(by: page)
            return true

        case .home:
            scroll(to: 0)
            return true

        case .end:
            scroll(to: wrappedLines().count)
            return true

        default:
            return false
        }
    }

    /// The wheel scrolls without focus.
    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .scrollUp:
            scroll(by: -1)
            return true

        case .scrollDown:
            scroll(by: 1)
            return true

        default:
            return false
        }
    }

    // MARK: - Wrapping & scrolling

    // Wrapped lines for the current bounds (cached by width).
    private var cachedLines: [[StyledRun]] = []
    private var cachedWidth: Int?

    private func wrappedLines() -> [[StyledRun]] {
        let width = contentWidth

        if cachedWidth == width {
            return cachedLines
        }

        let rendered = Markdown(markdown)
            .render(in: RenderContext(width: max(1, width), colorMode: .standard, markup: true))

        cachedLines = SGRDecoder.lines(from: rendered)
            .flatMap { Self.wrap($0, width: width) }
        cachedWidth = width
        return cachedLines
    }

    // Text width, leaving the last column to the indicator. Reserving it
    // unconditionally keeps wrapping independent of overflow (no feedback
    // loop between wrap width and indicator visibility).
    private var contentWidth: Int {
        max(1, bounds.size.width - 1)
    }

    private func scroll(by delta: Int) {
        scroll(to: scrollOffset + delta)
    }

    private func scroll(to target: Int) {
        let clamped = clampedOffset(target)

        if clamped != scrollOffset {
            scrollOffset = clamped
            setNeedsDisplay()
        }
    }

    private func clampedOffset(_ offset: Int) -> Int {
        max(0, min(offset, max(0, wrappedLines().count - bounds.size.height)))
    }

    /// Word-wraps styled runs to a width, breaking at spaces where
    /// possible (framework-internal, unit-tested directly).
    static func wrap(_ runs: [StyledRun], width: Int) -> [[StyledRun]] {
        guard width > 0 else {
            return [runs]
        }

        // Flatten to styled characters.
        var cells: [(character: Character, style: CellStyle)] = runs.flatMap { run in
            run.text.map { ($0, run.style) }
        }

        guard !cells.isEmpty else {
            return [[]]
        }

        var lines: [[StyledRun]] = []

        while !cells.isEmpty {
            if cells.count <= width {
                lines.append(Self.runs(from: cells))
                break
            }

            // A space right on the boundary lets the full window fit.
            if cells[width].character == " " {
                lines.append(Self.runs(from: Array(cells[0..<width])))
                cells.removeFirst(width + 1)
                continue
            }

            // Otherwise break at the last space inside the window.
            let window = cells[0..<width]

            if let breakIndex = window.lastIndex(where: { $0.character == " " }), breakIndex > 0 {
                lines.append(Self.runs(from: Array(cells[0..<breakIndex])))
                cells.removeFirst(breakIndex + 1)   // the space itself is consumed
            } else {
                lines.append(Self.runs(from: Array(window)))
                cells.removeFirst(width)
            }
        }

        return lines.isEmpty ? [[]] : lines
    }

    // Groups consecutive same-style characters back into runs.
    private static func runs(from cells: [(character: Character, style: CellStyle)]) -> [StyledRun] {
        var result: [StyledRun] = []

        for cell in cells {
            if var last = result.last, last.style == cell.style {
                last.text.append(cell.character)
                result[result.count - 1] = last
            } else {
                result.append(StyledRun(text: String(cell.character), style: cell.style))
            }
        }

        return result
    }
}
