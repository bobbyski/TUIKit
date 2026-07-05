/// A title carrying an optional keyboard mnemonic (accelerator).
///
/// The accelerator is marked in the source title with an `&` before the
/// accelerated character — the Windows/GTK/Qt convention:
///
/// ```text
///   "&File"   → File   with F as the mnemonic (Alt+F)
///   "S&ave"   → Save   with a as the mnemonic (Alt+A)
///   "R&&D"    → R&D    a literal ampersand, no mnemonic
/// ```
///
/// Parsing strips the markers so `display` is what gets drawn and measured;
/// `index` locates the accelerated character within `display` (for red
/// highlighting) and `key` is the lowercased letter that triggers it.
struct Accelerator: Equatable {
    /// The title with `&` markers removed — what is drawn and measured.
    let display: String

    /// Character offset of the accelerator within `display`, if any.
    let index: Int?

    /// The lowercased accelerator character (Alt+`key` triggers), if any.
    let key: Character?

    /// Parses an `&`-marked title. A lone `&` before a character marks the
    /// accelerator; `&&` is a literal `&`; a trailing `&` is dropped.
    init(_ title: String) {
        var display: [Character] = []
        var index: Int?
        var key: Character?

        var iterator = title.makeIterator()
        var pending = iterator.next()

        while let character = pending {
            if character == "&" {
                let next = iterator.next()

                if next == "&" {
                    // Escaped ampersand: emit one literal `&`.
                    display.append("&")
                    pending = iterator.next()
                } else if let next {
                    // Mark the first accelerator only; later `&x` emit x plainly.
                    if key == nil {
                        index = display.count
                        key = Character(next.lowercased())
                    }
                    display.append(next)
                    pending = iterator.next()
                } else {
                    // Trailing `&`: drop it.
                    pending = nil
                }
            } else {
                display.append(character)
                pending = iterator.next()
            }
        }

        self.display = String(display)
        self.index = index
        self.key = key
    }

    /// Whether `input` is this title's accelerator chord: Alt + the letter.
    func matches(_ input: KeyInput) -> Bool {
        guard let key, input.modifiers == .alt,
              case .character(let character) = input.key else {
            return false
        }

        return Character(character.lowercased()) == key
    }
}
