//
//  TUIFavorites.swift
//  TUIKit
//

import Foundation

/// A horizontal bar of saved links — a browser's bookmarks bar.
///
/// ```text
///   ★ Docs  ★ Search  ★ Mail                                     >>
///   ^^^^^^^^^^^^^^^^^^^^^^^^ fit on the row        overflow ─────┘
/// ```
///
/// Items are laid out left to right until the row runs out. Whatever does not
/// fit goes into a menu behind a `>>` button at the right end, so a bar that is
/// too narrow loses *access to nothing* — the same bargain `Toolbar` strikes
/// with its own overflow.
///
/// ```swift
/// let favorites = TUIFavorites()
/// favorites.items = [.init(title: "Docs"), .init(title: "Search")]
/// favorites.onActivate = { index in open(bookmarks[index]) }
/// ```
///
/// One row tall. Chrome rather than a focus stop: like a menu bar, it is
/// something you point at, and putting it in the Tab order would sit it
/// between the page and the controls people are actually cycling through.
@MainActor
public final class TUIFavorites: TUIView {

    /// One saved link.
    public struct Item: Sendable, Hashable {
        /// What the button shows.
        public var title: String

        /// Creates an item.
        ///
        /// - Parameter title: The button's label.
        public init(title: String) {
            self.title = title
        }
    }

    /// The links, left to right.
    public var items: [Item] = [] {
        didSet {
            if items != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// Called with the index of the item chosen, from the bar or the overflow
    /// menu. Indices are into `items`, so a caller never has to work out which
    /// of the two it came from.
    public var onActivate: (Int) -> Void = { _ in }

    /// Shown before every title. Empty for no marker.
    public var marker = "★" {
        didSet {
            if marker != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// What a bar with nothing on it says.
    public var emptyText = "" {
        didSet {
            if emptyText != oldValue {
                setNeedsDisplay()
            }
        }
    }

    /// The overflow button's label.
    private static let overflowLabel = " >> "

    /// The longest a title gets before it is truncated.
    private static let maximumTitleWidth = 20

    /// Creates an empty bar.
    public init() {
        super.init(frame: .zero)
    }

    /// Chrome, not a focus stop.
    public override var acceptsFirstResponder: Bool {
        false
    }

    // MARK: - Layout

    /// How the current width divides the items.
    private struct Plan {
        /// Widths of every item, in order.
        var widths: [Int]

        /// How many fit on the row.
        var visibleCount: Int

        /// Where the overflow button starts, when there is one.
        var overflowX: Int?
    }

    /// Works out what fits.
    ///
    /// Shared by drawing and hit testing so the two cannot disagree — the
    /// classic source of "clicking a button activates its neighbour".
    private func plan() -> Plan {
        let widths = items.map { width(of: $0) }
        let total = widths.reduce(0, +)

        guard total > bounds.size.width else {
            return Plan(widths: widths, visibleCount: items.count, overflowX: nil)
        }

        // Everything no longer fits, so the overflow button is now on the row
        // and has to be paid for out of the same width.
        let room = bounds.size.width - Self.overflowLabel.count
        var used = 0
        var count = 0

        for width in widths {
            guard used + width <= room else {
                break
            }

            used += width
            count += 1
        }

        return Plan(widths: widths, visibleCount: count, overflowX: max(0, room))
    }

    /// The label drawn for an item, marker included.
    private func label(for item: Item) -> String {
        let title = item.title.count > Self.maximumTitleWidth
            ? String(item.title.prefix(Self.maximumTitleWidth - 1)) + "…"
            : item.title

        return marker.isEmpty ? " \(title) " : " \(marker) \(title) "
    }

    /// Columns an item occupies.
    private func width(of item: Item) -> Int {
        DisplayWidth.of(label(for: item))
    }

    // MARK: - Drawing

    public override func draw(_ painter: Painter) {
        let theme = effectiveTheme
        painter.fill(bounds, with: TerminalCell(character: " ", style: theme.header))

        guard !items.isEmpty else {
            if !emptyText.isEmpty {
                painter.write(emptyText, at: .zero, style: theme.placeholder)
            }

            return
        }

        let plan = plan()
        var x = 0

        for index in 0..<plan.visibleCount {
            painter.write(label(for: items[index]), at: Point(x: x, y: 0), style: theme.header)
            x += plan.widths[index]
        }

        if let overflowX = plan.overflowX {
            painter.write(
                Self.overflowLabel,
                at: Point(x: overflowX, y: 0),
                style: theme.placeholder
            )
        }
    }

    // MARK: - Input

    public override func mouseEvent(_ mouse: MouseInput) -> Bool {
        guard mouse.action == .press, mouse.button == .left, mouse.position.y == 0 else {
            return false
        }

        let plan = plan()

        if let overflowX = plan.overflowX, mouse.position.x >= overflowX {
            openOverflowMenu(plan: plan)
            return true
        }

        var x = 0

        for index in 0..<plan.visibleCount {
            if mouse.position.x >= x, mouse.position.x < x + plan.widths[index] {
                onActivate(index)
                return true
            }

            x += plan.widths[index]
        }

        return false
    }

    /// Shows whatever did not fit, as a menu under the `>>`.
    private func openOverflowMenu(plan: Plan) {
        guard plan.visibleCount < items.count, let window = owningWindow else {
            return
        }

        let menu = Menu("")

        for index in plan.visibleCount..<items.count {
            // The index is captured, not the position in the menu, so the
            // callback means the same thing however the bar is sized.
            menu.addItem(items[index].title) { [weak self] in
                self?.onActivate(index)
            }
        }

        let origin = originInWindow(window)
        window.presentContextMenu(
            menu,
            at: origin + Point(x: plan.overflowX ?? 0, y: 0)
        )
    }

    /// This view's origin in window coordinates.
    private func originInWindow(_ window: Window) -> Point {
        var origin = Point.zero
        var current: TUIView? = self

        while let view = current, view !== window {
            origin = origin + view.frame.origin
            current = view.superview
        }

        return origin
    }
}
