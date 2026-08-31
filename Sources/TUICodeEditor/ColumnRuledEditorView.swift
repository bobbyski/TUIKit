import CodeEditorCore
import TUIKit

/// An editor whose COLUMNS mean something, shown as bands of colour.
///
/// ```text
///   1 ──── 6 │ 7 │ 8 ─── 11 │ 12 ───────────── 72 │ 73 ─── 80
///   sequence  ind   Area A    Area B                ignored
/// ```
///
/// Fixed-format COBOL is the case that needs it: text past column 72 is
/// discarded by every compiler, so an over-long statement looks correct and
/// behaves differently. A ruler line would say where the boundary is; a band
/// says which side of it you are on, for every line at once, without costing a
/// row.
///
/// A SUBCLASS rather than a fork, the way the GUI does it: everything an
/// editor already knows — folding, the change ribbon, diagnostics, the
/// clipboard, undo — is inherited, and this adds a background.
///
/// **The colours come from the theme where the theme can supply them.** On a
/// truecolor terminal each band is a shade of the editor's own background, so
/// the bands read as one surface with slightly different ground rather than as
/// stripes. Where the theme has no real colour to shade — a 16-colour palette,
/// a `.standard` background — there is nothing subtle available, and the bands
/// fall back to named colours, which are gaudy and legible. Gaudy beats
/// invisible: a band nobody can see is a band that is not there.
@MainActor
public final class ColumnRuledEditorView: CodeEditorView {
    /// One stretch of columns that means something.
    public struct ColumnBand: Equatable, Sendable {
        /// Columns it covers, ZERO-based and half-open, so it can be compared
        /// with a character index directly. `nil` upper bound means "to the
        /// end of the line", which is what an ignored tail is.
        public var columns: Range<Int>

        /// How strongly it should stand out.
        public var emphasis: Emphasis

        /// What it is, for anything that wants to say so.
        public var name: String

        /// How much a band should draw attention.
        public enum Emphasis: Equatable, Sendable {
            /// Ordinary code. The editor's own ground.
            case none

            /// Structural, but not a mistake — a sequence area, an Area A.
            case subtle

            /// A column whose ONE character changes what the line is.
            ///
            /// COBOL's indicator column is the case: a `*` there comments the
            /// whole line, a `-` continues the previous one, and a space means
            /// code. It is one character wide, so it needs to be findable
            /// without counting — which it is not when it shades the same as
            /// the sequence area it sits against.
            case marker

            /// Text the compiler will not see. This is the one worth noticing.
            case warning
        }

        /// Creates a band.
        public init(columns: Range<Int>, emphasis: Emphasis, name: String) {
            self.columns = columns
            self.emphasis = emphasis
            self.name = name
        }
    }

    /// How much of the column rule to paint.
    ///
    /// The bands are useful while learning a fixed format's areas and while
    /// laying code out; they are noise to someone who has typed COBOL for
    /// thirty years and only wants to know when a line has run past the
    /// margin. So the middle setting keeps the one band that reports a
    /// mistake and drops the four that describe the format.
    public enum GuideMode: String, CaseIterable, Sendable {
        /// Every band: the areas and the overflow.
        case all

        /// Only the bands that mark text the compiler will not see.
        case overflowOnly

        /// No bands at all — an ordinary editor with COBOL colouring.
        case none

        /// Menu/popup wording.
        public var title: String {
            switch self {
            case .all: "All Guides"
            case .overflowOnly: "Overflow Only"
            case .none: "No Guides"
            }
        }
    }

    /// Which bands are painted. Defaults to all of them.
    public var guideMode: GuideMode = .all {
        didSet {
            if guideMode != oldValue {
                refreshBandTints()
                setNeedsDisplay()
            }
        }
    }

    /// The bands, in column order. Empty means an ordinary editor.
    public var bands: [ColumnBand] = [] {
        didSet {
            if bands != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Fixed-format COBOL's areas.
    ///
    /// Columns 1–6 are the sequence area (numbering, ignored), 7 is the
    /// indicator, 8–11 Area A, 12–72 Area B, and anything from 73 on is
    /// discarded by the compiler.
    public static var cobolFixedFormat: [ColumnBand] {
        [
            ColumnBand(columns: 0..<6, emphasis: .subtle, name: "sequence"),
            ColumnBand(columns: 6..<7, emphasis: .marker, name: "indicator"),
            ColumnBand(columns: 7..<11, emphasis: .none, name: "Area A"),
            ColumnBand(columns: 11..<72, emphasis: .none, name: "Area B"),
            ColumnBand(columns: 72..<Int.max, emphasis: .warning, name: "ignored"),
        ]
    }

    /// Creates an editor with column bands.
    ///
    /// - Parameters:
    ///   - text: Initial contents.
    ///   - language: Syntax language identifier.
    ///   - bands: The columns that mean something.
    public init(text: String = "", language: String = "", bands: [ColumnBand] = []) {
        self.bands = bands
        super.init(text: text, language: language)
        refreshBandTints()
    }

    /// The band a column falls in, when any.
    ///
    /// - Parameter column: Zero-based column.
    public func band(atColumn column: Int) -> ColumnBand? {
        bands.first { $0.columns.contains(column) }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        refreshBandTints()
    }

    public override func draw(_ painter: Painter) {
        refreshBandTints()
        super.draw(painter)
    }

    // The bands, expressed as the base class's own column tints — so they are
    // painted by the same code that paints a diff's two halves, and syntax
    // colours resolve over them exactly the same way.
    private func refreshBandTints() {
        let shown: [ColumnBand]

        switch guideMode {
        case .all: shown = bands
        case .overflowOnly: shown = bands.filter { $0.emphasis == .warning }
        case .none: shown = []
        }

        guard !shown.isEmpty else {
            if !columnTints.isEmpty {
                columnTints = [:]
            }

            return
        }

        let width = max(1, textAreaWidth)
        let palette = Self.palette(over: effectiveTheme.base)

        let tints: [ColumnTint] = shown.compactMap { band in
            guard let color = palette[band.emphasis] else {
                return nil
            }

            let upper = band.columns.upperBound == Int.max ? width : min(band.columns.upperBound, width)

            guard band.columns.lowerBound < upper else {
                return nil
            }

            return ColumnTint(columns: band.columns.lowerBound..<upper, color: color)
        }

        // Every line, because a column means the same thing on all of them —
        // that is what makes it a column rule rather than a decoration.
        let lines = max(1, lineCount)
        var applied: [Int: [ColumnTint]] = [:]

        for line in 0..<lines {
            applied[line] = tints
        }

        if applied != columnTints {
            columnTints = applied
        }
    }

    /// Band colours for a background.
    ///
    /// Shades of the ground when there is a real colour to shade, named
    /// colours when there is not — see the type's own note. Exposed so a host
    /// can show the same colours in a legend without guessing at them.
    ///
    /// - Parameter base: The editor's ordinary text style.
    public static func palette(over base: CellStyle) -> [ColumnBand.Emphasis: TerminalColor] {
        guard case .rgb(let red, let green, let blue) = base.background else {
            // A 16-colour palette has no shades to offer, so the bands take
            // colours that cannot be mistaken for the ground.
            return [
                .subtle: .named(.blue),
                .marker: .named(.cyan),
                .warning: .named(.red),
            ]
        }

        return [
            .subtle: shade(red: red, green: green, blue: blue, by: 18),
            // Twice the sequence area's step, so the two read as separate
            // bands where they touch. One column is not much to look at;
            // matching its neighbour makes it nothing at all.
            .marker: shade(red: red, green: green, blue: blue, by: 40),
            .warning: warning(red: red, green: green, blue: blue),
        ]
    }

    // A lighter or darker version of the ground, whichever direction has room:
    // lightening a near-white background produces the same near-white.
    private static func shade(red: UInt8, green: UInt8, blue: UInt8, by amount: Int) -> TerminalColor {
        let luma = (299 * Int(red) + 587 * Int(green) + 114 * Int(blue)) / 1000
        let delta = luma < 128 ? amount : -amount

        return .rgb(
            red: UInt8(clamping: Int(red) + delta),
            green: UInt8(clamping: Int(green) + delta),
            blue: UInt8(clamping: Int(blue) + delta)
        )
    }

    // The ground pushed towards red, rather than a flat red: the text on it is
    // ordinary syntax-coloured code and still has to be readable.
    private static func warning(red: UInt8, green: UInt8, blue: UInt8) -> TerminalColor {
        .rgb(
            red: UInt8(clamping: Int(red) + 45),
            green: UInt8(clamping: Int(green) - 10),
            blue: UInt8(clamping: Int(blue) - 10)
        )
    }
}
