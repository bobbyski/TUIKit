/// The preferences dialog: pages behind a selector, one dialog.
///
/// ```text
///   ┌─ Preferences ────────────────┐   ┌─ Preferences ───────────────┐
///   │  ⚙ General   ✎ Editor        │   │ ▸ General │ (page content)  │
///   │ ────────────────────────────  │   │   Editor  │                 │
///   │ (the selected page)           │   │   Network │                 │
///   │                     [ Done ]  │   │                   [ Done ]  │
///   └──────────────────────────────┘   └─────────────────────────────┘
///        `.toolbar` selector                 `.split` selector
/// ```
///
/// Add pages — a title, an icon, a content view — and the dialog owns the
/// switching: a `Toolbox` strip across the top (`.toolbar`, the modern
/// look) or a `SidebarList` beside the pages (`.split`, the legacy look).
/// Add a Done button like any dialog; bind the pages' controls to a
/// `Preferences` store and the two halves of the settings story meet.
///
/// ```swift
/// let preferences = PreferencesDialog(style: .toolbar)
/// preferences.addPage("General", icon: "⚙", content: generalForm)
/// preferences.addPage("Editor", icon: "✎", content: editorForm)
/// preferences.addButton("&Done", isDefault: true)
/// app.present(preferences)
/// preferences.sizeToFit(in: app.desktop.bounds.size)
/// ```
@MainActor
public final class PreferencesDialog: Dialog {
    /// How the pages are picked.
    public enum SelectorStyle: Hashable, Sendable {
        /// An icon-and-caption strip across the top; pages below.
        case toolbar

        /// A list down the left; pages beside it.
        case split
    }

    /// How the pages are picked.
    public let selectorStyle: SelectorStyle

    /// The page titles, in order.
    public var pageTitles: [String] {
        pages.map(\.title)
    }

    /// The selected page.
    public private(set) var selectedIndex = 0

    /// Called when the shown page changes.
    public var onPageChanged: (Int) -> Void = { _ in }

    private var pages: [(title: String, icon: Character, content: TUIView)] = []
    private let pageHost = TUIView()
    private let strip = Toolbox(axis: .horizontal, tools: [])
    private let list = SidebarList(items: [])

    /// Creates a preferences dialog.
    ///
    /// - Parameters:
    ///   - title: Window title. Defaults to "Preferences".
    ///   - style: Toolbar strip (the default) or split list.
    public init(title: String = "Preferences", style: SelectorStyle = .toolbar) {
        selectorStyle = style
        super.init(title: title, message: "")

        switch style {
        case .toolbar:
            let column = VStack(spacing: 0)
            strip.minimumSize = Size(width: 0, height: 1)
            strip.maximumSize = Size(width: Int.max, height: 1)
            let rule = Divider(axis: .horizontal)
            rule.minimumSize = Size(width: 0, height: 1)
            rule.maximumSize = Size(width: Int.max, height: 1)
            column.addSubview(strip)
            column.addSubview(rule)
            column.addSubview(pageHost)
            column.anchors = .fill()
            body.addSubview(column)

            strip.onSelectionChanged = { [weak self] index in
                self?.select(index, notify: true)
            }

        case .split:
            let split = SplitView(axis: .horizontal, first: list, second: pageHost, dividerPosition: 14)
            split.minimumFirstLength = 8
            split.minimumSecondLength = 16
            split.anchors = .fill()
            body.addSubview(split)

            list.onSelectionChanged = { [weak self] index in
                if let index {
                    self?.select(index, notify: true)
                }
            }
        }
    }

    /// Adds a page.
    ///
    /// - Parameters:
    ///   - title: The page's name in the selector.
    ///   - icon: The glyph beside it.
    ///   - content: The page.
    /// - Returns: The page's index.
    @discardableResult
    public func addPage(_ title: String, icon: Character = "•", content: TUIView) -> Int {
        content.anchors = .fill()
        content.isHidden = !pages.isEmpty
        pageHost.addSubview(content)
        pages.append((title, icon, content))

        switch selectorStyle {
        case .toolbar:
            strip.tools = pages.map { page in
                Toolbox.Tool(glyph: page.icon, caption: page.title)
            }

        case .split:
            list.items = pages.map { page in
                SidebarItem(icon: page.icon, title: page.title)
            }
        }

        return pages.count - 1
    }

    /// Shows a page.
    ///
    /// - Parameters:
    ///   - index: The page.
    ///   - notify: Whether `onPageChanged` fires. Defaults to silent.
    public func select(_ index: Int, notify: Bool = false) {
        guard pages.indices.contains(index), index != selectedIndex || pages.count == 1 else {
            if pages.indices.contains(index), index == selectedIndex { return }
            return
        }

        for (position, page) in pages.enumerated() {
            page.content.isHidden = position != index
        }

        selectedIndex = index
        strip.select(index)
        list.select(index)
        pageHost.setNeedsLayout()
        pageHost.setNeedsDisplay()

        if notify {
            onPageChanged(index)
        }
    }

    /// Room for the selector, the largest page, the buttons, and the title.
    public override var preferredSize: Size {
        let base = super.preferredSize   // title + buttons never get cropped
        let pageSizes = pages.map { $0.content.intrinsicContentSize ?? Size(width: 30, height: 6) }
        let pageWidth = pageSizes.map(\.width).max() ?? 30
        let pageHeight = pageSizes.map(\.height).max() ?? 6

        switch selectorStyle {
        case .toolbar:
            let stripWidth = strip.intrinsicContentSize?.width ?? 20
            return Size(
                width: max(max(pageWidth, stripWidth) + 6, base.width),
                height: max(pageHeight + 7, base.height)
            )

        case .split:
            return Size(
                width: max(pageWidth + 14 + 7, base.width),
                height: max(max(pageHeight, pages.count * 2) + 5, base.height)
            )
        }
    }
}
