/// Modal window with a message and default/cancel actions.
///
/// A dialog is an ordinary `Window` wearing `Panel` chrome, so modality is
/// the window stack's existing rule: present it with `app.present(_:)` and
/// it owns all input until dismissed. Every button runs its action and then
/// `onDismiss`; the application decides what dismissal means (usually
/// `app.dismiss(dialog)`).
///
/// ```swift
/// let dialog = Dialog(title: "Delete file?", message: "This cannot be undone.")
/// dialog.addButton("Cancel", isCancel: true)
/// dialog.addButton("Delete", isDefault: true) { model.delete() }
/// dialog.onDismiss = { [weak app] in app?.dismiss(dialog) }
/// dialog.sizeToFit(in: screenSize)
/// app.present(dialog)
/// ```
///
/// Keys: Tab cycles the buttons, Return activates the focused control (the
/// default button starts focused), Esc activates the cancel button. When
/// focus is on a control that consumes Return (a text field, a list), the
/// default button still answers Return through the cold-key pass.
@MainActor
open class Dialog: Window {
    /// Called after any button's action; wire this to dismissal.
    public var onDismiss: () -> Void = {}

    /// Flexible region between the message and the buttons.
    ///
    /// Empty in a plain alert; dialog subclasses (like `FileDialog`) put
    /// their content here.
    public let body = TUIView()

    /// Buttons in the order added (rendered left to right).
    public private(set) var buttons: [Button] = []

    /// The button Return activates when nothing else consumes it.
    public private(set) var defaultButton: Button?

    /// The button Esc activates.
    public private(set) var cancelButton: Button?

    /// Border variant for the dialog frame.
    ///
    /// Defaults to `.single`: dialogs keep a single-line frame regardless of
    /// the theme's window border (e.g. Turbo's double frame).
    public var borderStyle: BorderStyle = .single {
        didSet {
            panel.borderStyleOverride = borderStyle
        }
    }

    /// Whether dragging the title row moves the dialog.
    public var isMovable = true

    /// Whether dragging the bottom-right corner resizes the dialog.
    ///
    /// Off by default (alerts are fixed-size); content-heavy dialogs like
    /// `FileDialog` turn it on. Enabling it shows the corner resize handle.
    public var isResizable = false {
        didSet {
            panel.showsResizeHandle = isResizable
        }
    }

    /// Smallest size a resize drag can reach.
    public var minimumWindowSize = Size(width: 24, height: 8)

    // Chrome and layout: message lines sit tight at the top, a flexible
    // gap absorbs extra height, buttons sit at the bottom right.
    private let panel: Panel

    // In-flight chrome drag (title move or corner resize).
    private enum ChromeDrag {
        case move(grab: Point)
        case resize
    }

    private var activeDrag: ChromeDrag?
    private let stack = VStack(spacing: 0, insets: EdgeInsets(left: 1, right: 1))
    private let buttonRow = HStack(spacing: 2)
    private let messageLineCount: Int

    /// Creates a dialog.
    ///
    /// - Parameters:
    ///   - title: Panel title.
    ///   - message: Body text; newlines produce multiple lines.
    public init(title: String, message: String = "") {
        self.panel = Panel(title)

        let lines = message.isEmpty ? [] : message.split(separator: "\n", omittingEmptySubsequences: false)
        self.messageLineCount = lines.count

        super.init(frame: .zero)

        isModal = true   // dialogs own all input while key

        panel.borderStyleOverride = borderStyle   // single frame by default
        panel.anchors = .fill()
        addSubview(panel)

        for line in lines {
            stack.addSubview(Label(String(line)))
        }

        stack.addSubview(body)   // flexible: absorbs extra height between message and buttons
        buttonRow.addSubview(TUIView())   // flexible spacer right-aligns buttons
        stack.addSubview(buttonRow)

        stack.anchors = .fill()
        panel.content.addSubview(stack)
    }

    /// Adds a button; the first default button receives initial focus.
    ///
    /// - Parameters:
    ///   - title: Button title.
    ///   - isDefault: Whether Return activates it from anywhere. Default
    ///     buttons draw as a filled pill from the theme's `defaultButton` slot.
    ///   - isCancel: Whether Esc activates it.
    ///   - isDestructive: Whether the button is a dangerous choice; draws as a
    ///     filled pill from the theme's `destructiveButton` slot.
    ///   - action: Called on activation, before `onDismiss`.
    /// - Returns: The created button.
    @discardableResult
    public func addButton(
        _ title: String,
        isDefault: Bool = false,
        isCancel: Bool = false,
        isDestructive: Bool = false,
        action: @escaping () -> Void = {}
    ) -> Button {
        let button = Button(title)

        button.onActivate = { [weak self] in
            action()
            self?.onDismiss()
        }

        if isDestructive {
            button.role = .destructive
        } else if isDefault {
            button.role = .default
        }

        buttons.append(button)
        buttonRow.addSubview(button)

        if isDefault, defaultButton == nil {
            defaultButton = button
            makeFirstResponder(button)
        }

        if isCancel, cancelButton == nil {
            cancelButton = button
        }

        return button
    }

    /// The smallest frame that fits the chrome, message, and buttons.
    public var preferredSize: Size {
        let messageWidth = stack.subviews
            .compactMap { ($0 as? Label)?.intrinsicContentSize?.width }
            .max() ?? 0

        // The row is [flexible spacer, button, button, …] with spacing 2,
        // so there are `count` gaps (one after the spacer), not count - 1.
        let buttonsWidth = buttons.reduce(0) { $0 + ($1.intrinsicContentSize?.width ?? 0) }
            + buttons.count * 2

        // Border (2) + stack side insets (2) around the widest inner line;
        // the title needs its border decoration too.
        let width = max(max(messageWidth, buttonsWidth) + 4, panel.title.count + 8)

        // The button row is as tall as its tallest button — 2 under a theme
        // with button drop shadows, 1 otherwise. (Theme-dependent, so call
        // `sizeToFit` after presenting when the app theme differs.)
        let buttonRowHeight = buttons.compactMap { $0.intrinsicContentSize?.height }.max() ?? 1

        // Border (2) + message lines + one blank gap row + button row.
        let height = 2 + messageLineCount + (messageLineCount > 0 ? 1 : 0) + buttonRowHeight

        return Size(width: width, height: height)
    }

    /// Sizes the dialog to its preferred size, centered in a container.
    ///
    /// - Parameter container: Screen (or parent) size in cells.
    public func sizeToFit(in container: Size) {
        let size = Size(
            width: min(preferredSize.width, max(0, container.width - 4)),
            height: min(preferredSize.height, max(0, container.height - 2))
        )

        frame = Rect(
            x: max(0, (container.width - size.width) / 2),
            y: max(0, (container.height - size.height) / 2),
            width: size.width,
            height: size.height
        )
    }

    /// Esc activates the cancel button before anything else sees the key.
    public override func handleHotKey(_ key: KeyInput) -> Bool {
        guard key.key == .escape, key.modifiers.isEmpty, let cancelButton else {
            return false
        }

        cancelButton.activate()
        return true
    }

    /// Return activates the default button when nothing else consumed it.
    public override func handleColdKey(_ key: KeyInput) -> Bool {
        guard key.key == .enter, key.modifiers.isEmpty, let defaultButton else {
            return false
        }

        defaultButton.activate()
        return true
    }

    /// Title-row presses move the dialog; the bottom-right corner resizes it.
    ///
    /// Only presses on chrome no control consumed bubble up to here, and the
    /// window captures the gesture, so a drag tracks even when the pointer
    /// briefly outruns the frame.
    open override func mouseEvent(_ mouse: MouseInput) -> Bool {
        switch mouse.action {
        case .press where mouse.button == .left:
            if isResizable,
               mouse.position.x == bounds.size.width - 1,
               mouse.position.y == bounds.size.height - 1 {
                activeDrag = .resize
                return true
            }

            if isMovable, mouse.position.y == 0 {
                activeDrag = .move(grab: mouse.position)
                return true
            }

            return false

        case .drag:
            switch activeDrag {
            case .move(let grab):
                let delta = mouse.position - grab
                frame = Rect(
                    origin: Point(
                        x: frame.origin.x + delta.x,
                        y: max(0, frame.origin.y + delta.y)
                    ),
                    size: frame.size
                )
                return true

            case .resize:
                frame = Rect(
                    origin: frame.origin,
                    size: Size(
                        width: max(minimumWindowSize.width, mouse.position.x + 1),
                        height: max(minimumWindowSize.height, mouse.position.y + 1)
                    )
                )
                return true

            case nil:
                return false
            }

        case .release:
            guard activeDrag != nil else {
                return false
            }

            activeDrag = nil
            return true

        default:
            return false
        }
    }
}
