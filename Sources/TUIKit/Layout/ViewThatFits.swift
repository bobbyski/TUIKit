/// Shows the first child that fits — a layout that degrades on purpose.
///
/// ```text
///   wide:    [ Save the document to disk ]
///   medium:  [ Save document ]
///   narrow:  [ Save ]
/// ```
///
/// Give it candidates from most to least elaborate; at layout it shows the
/// first whose natural size fits the available space on `axis`, and hides
/// the rest (hidden candidates leave the focus order). A candidate with no
/// `intrinsicContentSize` always fits, so the last one can be a flexible
/// catch-all. Terminals run from 80 to 250 columns, which makes this more
/// useful here than it ever was on a desktop.
///
/// ```swift
/// let save = ViewThatFits(axis: .horizontal, candidates: [
///     Button("Save the document to disk") { save() },
///     Button("Save document") { save() },
///     Button("Save") { save() },
/// ])
/// ```
@MainActor
public final class ViewThatFits: TUIView {
    /// Which dimension(s) must fit.
    public enum Axis: Hashable, Sendable {
        /// Width must fit.
        case horizontal

        /// Height must fit.
        case vertical

        /// Both must fit.
        case both
    }

    /// Which dimension(s) must fit.
    public var axis: Axis {
        didSet {
            if axis != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// The candidates, most elaborate first.
    public private(set) var candidates: [TUIView]

    /// Index of the candidate currently shown, once laid out.
    public private(set) var chosenIndex: Int?

    /// Called when layout switches to a different candidate.
    public var onChoiceChanged: (Int) -> Void = { _ in }

    /// Creates the container.
    ///
    /// - Parameters:
    ///   - axis: Which dimension(s) must fit. Defaults to `.both`.
    ///   - candidates: The candidates, most elaborate first.
    public init(axis: Axis = .both, candidates: [TUIView]) {
        self.axis = axis
        self.candidates = candidates
        super.init(frame: .zero)

        for candidate in candidates {
            candidate.isHidden = true
            addSubview(candidate)
        }
    }

    /// The narrowest candidate's width with the tallest candidate's height:
    /// enough room for any of them vertically, while allowing the layout
    /// around it to go narrow.
    public override var intrinsicContentSize: Size? {
        let sizes = candidates.compactMap(\.intrinsicContentSize)

        guard !sizes.isEmpty else {
            return nil
        }

        return Size(width: sizes.map(\.width).min() ?? 0, height: sizes.map(\.height).max() ?? 0)
    }

    /// Picks the first candidate that fits and gives it the whole bounds.
    public override func layoutSubviews() {
        guard !candidates.isEmpty else {
            return
        }

        let index = candidates.firstIndex { fits($0) } ?? candidates.count - 1

        for (position, candidate) in candidates.enumerated() {
            candidate.isHidden = position != index
        }

        candidates[index].frame = bounds

        if index != chosenIndex {
            chosenIndex = index
            onChoiceChanged(index)
        }
    }

    private func fits(_ candidate: TUIView) -> Bool {
        guard let size = candidate.intrinsicContentSize else {
            return true
        }

        switch axis {
        case .horizontal:
            return size.width <= bounds.size.width

        case .vertical:
            return size.height <= bounds.size.height

        case .both:
            return size.width <= bounds.size.width && size.height <= bounds.size.height
        }
    }
}
