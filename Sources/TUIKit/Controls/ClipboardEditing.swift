/// A view that can cut, copy and paste through the app clipboard.
///
/// Exists so a host can bind ONE set of clipboard commands and have them land
/// wherever focus is, instead of hard-wiring them to a particular control.
/// OmegaCLIDE's Edit menu did the latter — Copy and Paste called the active
/// EDITOR — which meant the commands were wrong the moment focus was in the
/// Find field, and the shortcuts were missing entirely.
@MainActor
public protocol ClipboardEditing: TUIView {
    /// Copies the selection, or the whole contents for a control that has a
    /// cursor and no selection.
    func clipboardCopy()

    /// Copies and then removes.
    func clipboardCut()

    /// Inserts the clipboard at the caret.
    func clipboardPaste()
}

public extension Window {
    /// The focused view that can handle clipboard commands, walking up from
    /// the first responder.
    ///
    /// Walks UP because focus often sits on a leaf inside a control that owns
    /// the text — and a command that only worked when the exact right view
    /// held focus would be a command that mostly does not work.
    var focusedClipboardEditor: (any ClipboardEditing)? {
        var candidate: TUIView? = firstResponder

        while let view = candidate {
            if let editor = view as? any ClipboardEditing {
                return editor
            }

            candidate = view.superview
        }

        return nil
    }
}
