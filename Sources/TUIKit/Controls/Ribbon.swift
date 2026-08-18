/// A `Toolbar` divided into titled groups.
///
/// ```text
///   [ ▶ ] [ ■ ] [ ↺ ] │ [ Config ▾ ] [ 🔍 ] │            ⇥            [ ⚙ ]
///    Run  Stop Reset  │   Scheme    Search  │                       Settings
///   └─── Build ───────┘ └──── Project ─────┘
/// ```
///
/// A ribbon goes ANYWHERE — it is an ordinary view, placed in a stack or a
/// pane like any other. That is what separates it from a ``Toolbar``, which
/// is handed to a window (`window.setToolbar(_:)`) and always sits across the
/// top. Same items, same layout, different question about placement: a
/// toolbar's is already answered, a ribbon's is the caller's.
///
/// Bobby: *"they are almost the same."* They are, and this leans on that
/// rather than working around it: a ribbon IS a toolbar plus group names, so
/// it wraps one instead of reimplementing the layout, the overflow, the
/// focus order and the flexible-space arithmetic. Everything `Toolbar` learns
/// later, a ribbon gets.
///
/// What the group adds is a caption row and a divider between groups — which
/// the toolbar could already draw, so a ribbon is mostly bookkeeping about
/// which items belong to which name.
///
/// Group captions cost **one more row** on top of whatever the display mode
/// needs, which is why a ribbon is a deliberate choice in a terminal and not
/// the default shape of a command bar.
@MainActor
public final class Ribbon: TUIView {
    /// The bar the ribbon is built on. Set its `displayMode` and `style`.
    public let toolbar = Toolbar()

    /// Whether group captions draw.
    ///
    /// Off makes a ribbon exactly a toolbar with dividers — worth having when
    /// a window is short, since it gives the row back.
    public var showsGroupTitles = true {
        didSet {
            if showsGroupTitles != oldValue {
                superview?.setNeedsLayout()
                setNeedsLayout()
                setNeedsDisplay()
            }
        }
    }

    // Group names in order, with the item range each covers.
    private var groups: [(title: String, range: Range<Int>)] = []

    /// Creates an empty ribbon.
    public override init(frame: Rect = .zero) {
        super.init(frame: frame)
        toolbar.anchors = .fill()
        addSubview(toolbar)
    }

    /// Appends a named group of items.
    ///
    /// A `│` divider is inserted between groups automatically — the caller
    /// should not add one, or there will be two.
    ///
    /// - Parameters:
    ///   - title: The caption under the group.
    ///   - items: What goes in it, in order.
    public func addGroup(_ title: String, items: [ToolbarItem]) {
        if !groups.isEmpty {
            toolbar.add(.divider())
        }

        let start = toolbar.items.count

        for item in items {
            toolbar.add(item)
        }

        groups.append((title: title, range: start..<toolbar.items.count))
        superview?.setNeedsLayout()
        setNeedsLayout()
        setNeedsDisplay()
    }

    /// Group names in order — test support.
    public var groupTitles: [String] {
        groups.map(\.title)
    }

    /// The toolbar's rows plus a caption row when captions show.
    public override var intrinsicContentSize: Size? {
        Size(width: toolbar.intrinsicContentSize?.width ?? 0, height: rowCount)
    }

    /// Rows the ribbon needs.
    public var rowCount: Int {
        toolbar.rowCount + (showsGroupTitles && !groups.isEmpty ? 1 : 0)
    }

    /// Gives the toolbar every row but the caption's.
    public override func layoutSubviews() {
        let captionRows = showsGroupTitles && !groups.isEmpty ? 1 : 0
        toolbar.anchors = AnchorSet()
        toolbar.frame = Rect(
            x: 0,
            y: 0,
            width: bounds.size.width,
            height: max(0, bounds.size.height - captionRows)
        )
        toolbar.layoutIfNeeded()
    }

    /// Draws the group captions under the bar.
    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: TerminalCell(character: " ", style: theme.header))

        guard showsGroupTitles, !groups.isEmpty else {
            return
        }

        let row = bounds.size.height - 1
        var caption = theme.header
        caption.flags.insert(.dim)

        for group in groups {
            guard let span = toolbar.span(ofItems: group.range) else {
                continue   // the whole group overflowed
            }

            // Centred under its own items, and truncated to them: a caption
            // wider than its group would read as belonging to the next one.
            let text = Label.truncated(group.title, width: span.width)
            let x = span.x + max(0, (span.width - text.count) / 2)
            painter.write(text, at: Point(x: x, y: row), style: caption)
        }
    }
}
