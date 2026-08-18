import CodeEditorCore
import TUIKit

// Painting helpers. `draw` itself lives in the class (Swift forbids
// overriding in an extension); everything it delegates to is here, which is
// what keeps the class body readable.
extension CodeEditorView {
    /// Paints one document line's gutter cells.
    func paintGutter(_ painter: Painter, line: Int, row: Int, theme: ResolvedTheme) {
        var column = 0

        for band in gutterBands {
            for cell in band.cells(forLine: line, theme: theme) {
                painter.set(cell, at: Point(x: column, y: row))
                column += 1
            }
        }

        var separator = theme.base
        separator.flags.insert(.dim)
        painter.set(TerminalCell(character: "│", style: separator), at: Point(x: column, y: row))
    }

    /// Paints one document line's text, coloured, selected, and underlined.
    func paintLine(_ painter: Painter, line: Int, row: Int, theme: ResolvedTheme) {
        let characters = Array(engineDocument.line(at: line))
        let gutter = gutterColumns
        let trailing = trailingColumns
        let width = max(0, bounds.size.width - gutter - trailing - (drawsVerticalBar ? 1 : 0))
        let selection = engineSelection

        // A tinted line is the same line on a different ground: everything
        // below layers over THIS, so syntax colours survive inside a diff
        // block instead of being flattened to one colour.
        var base = theme.base

        if let tint = lineTints[line] {
            base.background = tint
            painter.fill(
                Rect(x: gutter, y: row, width: width, height: 1),
                with: TerminalCell(character: " ", style: base)
            )
        }

        // Column tints paint their own stretch of ground; the per-character
        // grounds below are then taken from whichever tint covers the column,
        // so syntax colours survive inside a side-by-side block too.
        let stretches = columnTints[line] ?? []

        for stretch in stretches {
            var style = base
            style.background = stretch.color

            let start = max(0, stretch.columns.lowerBound - leftColumn)
            let end = max(start, min(width, stretch.columns.upperBound - leftColumn))

            painter.fill(
                Rect(x: gutter + start, y: row, width: end - start, height: 1),
                with: TerminalCell(character: " ", style: style)
            )
        }

        func ground(atColumn column: Int) -> CellStyle {
            guard let stretch = stretches.first(where: { $0.columns.contains(column) }) else {
                return base
            }

            var style = base
            style.background = stretch.color
            return style
        }

        // One resolved style per character. Building the row this way stops
        // syntax, selection, and diagnostics fighting over the same cell —
        // they layer in a defined order instead.
        var styles = (0..<characters.count).map { ground(atColumn: $0) }

        for token in tokenStore.tokens(forLine: line) {
            for index in token.range.lowerBound..<min(token.range.upperBound, characters.count) {
                styles[index] = syntaxTheme.style(for: token.scope).cellStyle(over: ground(atColumn: index))
            }
        }

        for diagnostic in diagnosticsBand.diagnostics.diagnostics(forLine: line) {
            let start = min(diagnostic.column, characters.count)
            let end = diagnostic.length > 0 ? min(start + diagnostic.length, characters.count) : characters.count

            for index in start..<max(start, end) {
                styles[index].flags.insert(.underline)
            }
        }

        if let selected = selectedColumns(on: line, selection: selection) {
            for index in selected where index < styles.count {
                styles[index] = theme.selection
            }
        }

        for column in 0..<width {
            let index = column + leftColumn

            guard index < characters.count else {
                break
            }

            painter.set(
                TerminalCell(character: characters[index], style: styles[index]),
                at: Point(x: gutter + column, y: row)
            )
        }

        if foldBand.map.isFolded(line) {
            var style = theme.base
            style.flags.insert(.dim)
            style.flags.insert(.inverse)
            let marker = " ⋯ "
            let start = gutter + max(0, characters.count - leftColumn) + 1

            for (offset, character) in marker.enumerated() where start + offset < bounds.size.width {
                painter.set(TerminalCell(character: character, style: style), at: Point(x: start + offset, y: row))
            }
        }

        paintTrailingNumber(painter, line: line, row: row, theme: theme)
        paintCaret(painter, line: line, row: row, characters: characters, theme: theme)
    }

    // The new file's number, down the right-hand edge. Right-aligned against
    // the text so the column reads as a column, with a space before the
    // scrollbar so the two never touch.
    private func paintTrailingNumber(_ painter: Painter, line: Int, row: Int, theme: ResolvedTheme) {
        let trailing = trailingColumns

        guard trailing > 0 else {
            return
        }

        var style = theme.base
        style.flags.insert(line == engineSelection.head.line ? .bold : .dim)

        var separator = theme.base
        separator.flags.insert(.dim)

        // A rule down the inside edge, mirroring the one after the left
        // gutter: the numbers are a gutter, and a gutter has an edge.
        let start = bounds.size.width - trailing - (drawsVerticalBar ? 1 : 0)
        painter.set(TerminalCell(character: "│", style: separator), at: Point(x: start, y: row))

        let text = (trailingNumbers[line].map(String.init) ?? "")
            .padded(to: trailing - 2, alignedRight: true) + " "

        for (offset, character) in text.enumerated() where start + 1 + offset < bounds.size.width {
            painter.set(TerminalCell(character: character, style: style), at: Point(x: start + 1 + offset, y: row))
        }
    }

    // The caret is an inverse cell (matching the old editor): TUIKit views
    // report no terminal cursor of their own.
    private func paintCaret(_ painter: Painter, line: Int, row: Int, characters: [Character], theme: ResolvedTheme) {
        guard isFirstResponder, engineSelection.isEmpty, engineSelection.head.line == line else {
            return
        }

        let column = engineSelection.head.column - leftColumn

        guard column >= 0, column < max(0, bounds.size.width - gutterColumns - (drawsVerticalBar ? 1 : 0)) else {
            return
        }

        let index = engineSelection.head.column
        let character = index < characters.count ? characters[index] : " "

        painter.set(
            TerminalCell(character: character, style: CellStyle(flags: .inverse)),
            at: Point(x: gutterColumns + column, y: row)
        )
    }

    /// The columns of a line the selection covers.
    func selectedColumns(on line: Int, selection: TextSelection) -> Range<Int>? {
        guard !selection.isEmpty else {
            return nil
        }

        let start = selection.start
        let end = selection.end

        guard line >= start.line, line <= end.line else {
            return nil
        }

        let length = engineDocument.line(at: line).count
        let from = line == start.line ? start.column : 0
        let to = line == end.line ? end.column : length

        return from..<max(from, to)
    }

    /// Paints the interior scrollbars, when the view owns them.
    func paintScrollbars(_ painter: Painter, theme: ResolvedTheme) {
        // The theme's scrollbar slot: foreground is the thumb, background
        // the track. Focused bars brighten, matching the rest of TUIKit.
        var track = theme.scrollbar
        track.foreground = theme.scrollbar.background
        var thumb = theme.scrollbar
        thumb.background = theme.scrollbar.foreground

        if !isFirstResponder {
            track.flags.insert(.dim)
            thumb.flags.insert(.dim)
        }

        // Arrow glyphs read against the track, the way the border-embedded
        // bars do — the two are the same control in two places and should not
        // look like different controls.
        var arrow = track
        arrow.foreground = thumb.background == .standard ? track.foreground : thumb.background

        if drawsVerticalBar, let run = ownVerticalRun() {
            let column = bounds.size.width - 1
            let (thumbStart, thumbLength) = run.thumb

            for y in run.start..<(run.start + run.length) {
                let inThumb = y >= thumbStart && y < thumbStart + thumbLength
                painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: column, y: y))
            }

            if run.hasArrows {
                painter.set(TerminalCell(character: "▴", style: arrow), at: Point(x: column, y: run.start))
                painter.set(TerminalCell(character: "▾", style: arrow), at: Point(x: column, y: run.start + run.length - 1))
            }
        }

        if drawsHorizontalBar, let run = ownHorizontalRun() {
            let row = bounds.size.height - 1
            let (thumbStart, thumbLength) = run.thumb

            for x in run.start..<(run.start + run.length) {
                let inThumb = x >= thumbStart && x < thumbStart + thumbLength
                painter.set(TerminalCell(character: " ", style: inThumb ? thumb : track), at: Point(x: x, y: row))
            }

            if run.hasArrows {
                painter.set(TerminalCell(character: "◂", style: arrow), at: Point(x: run.start, y: row))
                painter.set(TerminalCell(character: "▸", style: arrow), at: Point(x: run.start + run.length - 1, y: row))
            }
        }
    }


    /// The document line drawn on a screen row, folds applied.
    func documentLine(atRow row: Int) -> Int {
        let visible = visibleDocumentLines
        let first = visible.firstIndex(where: { $0 >= topLine }) ?? 0
        let index = first + max(0, row)

        guard index < visible.count else {
            return max(0, engineDocument.lineCount - 1)
        }

        return visible[index]
    }

    /// Turns a click inside the view into a document position.
    func position(at point: Point) -> TextPosition {
        let row = max(0, min(point.y, bounds.size.height - 1))
        let line = documentLine(atRow: row)
        let column = max(0, point.x - gutterColumns + leftColumn)
        return TextPosition(line: line, column: min(column, engineDocument.line(at: line).count))
    }

    /// Routes a gutter click to whichever band owns that column.
    ///
    /// - Returns: Whether a band consumed it.
    func handleGutterClick(at point: Point) -> Bool {
        var column = 0
        let line = documentLine(atRow: point.y)

        for band in gutterBands {
            if point.x >= column, point.x < column + band.width {
                return band.handleClick(onLine: line)
            }

            column += band.width
        }

        return false
    }
}
