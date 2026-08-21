/// Multi-step flows with validation and branching, on a `Navigator`.
///
/// ```text
///   ◂ Back   Account (step 2 of 4)
///   ───────────────────────────────
///   (the step's view)
///
///   Choose a user name to continue.         [ Back ] [ Next ▸ ]
/// ```
///
/// Each step has a title, a view, an optional `validate` that returns a
/// message to block Next, and an optional `next` that names the step to go
/// to (branching); without one the steps run in order. The footer shows
/// the validation message and the Back / Next / Finish buttons; Esc goes
/// back like the navigator it rides on.
///
/// ```swift
/// let wizard = Wizard(steps: [
///     .init(id: "welcome", title: "Welcome", view: welcome),
///     .init(id: "account", title: "Account", view: accountForm,
///           validate: { name.text.isEmpty ? "Choose a user name to continue." : nil }),
///     .init(id: "done", title: "All set", view: summary),
/// ])
/// wizard.onFinish = { install() }
/// ```
@MainActor
public final class Wizard: TUIView {
    /// One step.
    public struct Step {
        /// Stable name, used by `next` for branching.
        public var id: String

        /// Header title.
        public var title: String

        /// The step's view.
        public var view: TUIView

        /// Returns a message that blocks Next, or `nil` when the step is
        /// complete.
        public var validate: () -> String?

        /// Names the step that follows, or `nil` for the next in order.
        public var next: () -> String?

        /// Creates a step.
        public init(
            id: String,
            title: String,
            view: TUIView,
            validate: @escaping () -> String? = { nil },
            next: @escaping () -> String? = { nil }
        ) {
            self.id = id
            self.title = title
            self.view = view
            self.validate = validate
            self.next = next
        }
    }

    /// The steps, in default order.
    public let steps: [Step]

    /// Called when Finish is pressed on a step with no successor.
    public var onFinish: () -> Void = {}

    /// Called whenever the shown step changes, with its index in `steps`.
    public var onStepChanged: (Int) -> Void = { _ in }

    /// Index (into `steps`) of the step showing.
    public var currentIndex: Int {
        trail.last ?? 0
    }

    /// The step showing.
    public var currentStep: Step {
        steps[currentIndex]
    }

    /// The navigator carrying the steps (its header shows title and progress).
    public let navigator: Navigator

    /// The Back button.
    public let backButton: Button

    /// The Next / Finish button.
    public let nextButton: Button

    // Indices visited, in order — branching means "previous" is history,
    // not index minus one.
    private var trail: [Int] = [0]
    private let message = Label("")

    /// Creates a wizard.
    ///
    /// - Parameter steps: The steps; the first shows immediately.
    public init(steps: [Step]) {
        precondition(!steps.isEmpty, "a wizard needs at least one step")
        self.steps = steps
        navigator = Navigator(root: steps[0].view, title: "")
        backButton = Button("◂ &Back")
        nextButton = Button("&Next ▸")
        super.init(frame: .zero)

        navigator.showsHeader = true
        addSubview(navigator)
        addSubview(message)
        addSubview(backButton)
        addSubview(nextButton)

        backButton.onActivate = { [weak self] in self?.goBack() }
        nextButton.onActivate = { [weak self] in self?.goNext() }
        navigator.onDepthChanged = { [weak self] depth in
            // The navigator's own Back (Esc, header click) is a wizard Back.
            guard let self, depth < self.trail.count else { return }
            self.trail.removeLast(self.trail.count - depth)
            self.syncFooter()
            self.onStepChanged(self.currentIndex)
        }

        syncFooter()
    }

    /// Advances, exactly as Next does: validates, branches, or finishes.
    ///
    /// - Returns: `false` when validation blocked the move.
    @discardableResult
    public func goNext() -> Bool {
        if let problem = currentStep.validate() {
            message.text = problem
            message.setNeedsDisplay()
            return false
        }

        guard let target = successorIndex else {
            onFinish()
            return true
        }

        trail.append(target)
        navigator.push(steps[target].view, title: "")
        syncFooter()
        onStepChanged(target)
        return true
    }

    /// Returns to the previous step, exactly as Back does.
    ///
    /// - Returns: `false` on the first step.
    @discardableResult
    public func goBack() -> Bool {
        guard trail.count > 1 else {
            return false
        }

        // popping the navigator runs onDepthChanged, which trims the trail.
        return navigator.pop()
    }

    /// Whether the current step is the last one on its path.
    public var isOnFinalStep: Bool {
        successorIndex == nil
    }

    /// Header row, footer row, the step between.
    public override func layoutSubviews() {
        let width = bounds.size.width
        let height = bounds.size.height
        let nextWidth = nextButton.intrinsicContentSize?.width ?? 10
        let backWidth = backButton.intrinsicContentSize?.width ?? 10

        navigator.frame = Rect(x: 0, y: 0, width: width, height: max(0, height - 1))
        nextButton.frame = Rect(x: max(0, width - nextWidth), y: height - 1, width: nextWidth, height: 1)
        backButton.frame = Rect(x: max(0, width - nextWidth - 1 - backWidth), y: height - 1, width: backWidth, height: 1)
        message.frame = Rect(x: 1, y: height - 1, width: max(0, backButton.frame.minX - 2), height: 1)
    }

    /// The step's view plus header and footer.
    public override var intrinsicContentSize: Size? {
        guard let size = currentStep.view.intrinsicContentSize else {
            return nil
        }

        return Size(width: max(size.width, 40), height: size.height + 2)
    }

    // MARK: - State

    private var successorIndex: Int? {
        if let id = currentStep.next() {
            return steps.firstIndex { $0.id == id }
        }

        let following = currentIndex + 1
        return following < steps.count ? following : nil
    }

    private func syncFooter() {
        message.text = ""
        message.style = CellStyle(foreground: effectiveTheme.warningAccent)
        backButton.isHidden = trail.count <= 1
        nextButton.title = isOnFinalStep ? "&Finish" : "&Next ▸"
        navigator.setTitle("\(currentStep.title)  (step \(trail.count) of \(pathLength))")
        setNeedsLayout()
        setNeedsDisplay()
    }

    // Steps on the current path: the trail so far plus the default order
    // from here (branching may change it as the user goes).
    private var pathLength: Int {
        var count = trail.count
        var index = currentIndex

        while true {
            let step = steps[index]
            let nextIndex: Int?

            if let id = step.next() {
                nextIndex = steps.firstIndex { $0.id == id }
            } else {
                nextIndex = index + 1 < steps.count ? index + 1 : nil
            }

            guard let nextIndex, nextIndex != index, count < steps.count * 2 else {
                return count
            }

            count += 1
            index = nextIndex
        }
    }
}
