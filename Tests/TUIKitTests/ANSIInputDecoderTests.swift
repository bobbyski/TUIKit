import Testing
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private func bytes(_ text: String) -> [UInt8] {
    Array(text.utf8)
}

private let esc: UInt8 = 0x1B

// MARK: - Plain Keys

@Test func decodesPrintableASCII() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("a Z!"))

    #expect(events == [
        .key(KeyInput(key: .character("a"))),
        .key(KeyInput(key: .character(" "))),
        .key(KeyInput(key: .character("Z"))),
        .key(KeyInput(key: .character("!"))),
    ])
}

@Test func decodesEnterTabBackspace() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed([0x0D, 0x0A, 0x09, 0x7F, 0x08])

    #expect(events == [
        .key(KeyInput(key: .enter)),
        .key(KeyInput(key: .enter)),
        .key(KeyInput(key: .tab)),
        .key(KeyInput(key: .backspace)),
        .key(KeyInput(key: .backspace)),
    ])
}

@Test func decodesControlLetters() {
    var decoder = ANSIInputDecoder()

    // Ctrl+C (0x03) and Ctrl+X (0x18).
    let events = decoder.feed([0x03, 0x18])

    #expect(events == [
        .key(KeyInput(key: .character("c"), modifiers: .control)),
        .key(KeyInput(key: .character("x"), modifiers: .control)),
    ])
}

@Test func decodesUTF8MultibyteCharacters() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("é✓🙂"))

    #expect(events == [
        .key(KeyInput(key: .character("é"))),
        .key(KeyInput(key: .character("✓"))),
        .key(KeyInput(key: .character("🙂"))),
    ])
}

@Test func utf8SplitAcrossChunksStillDecodes() {
    var decoder = ANSIInputDecoder()
    let smiley = bytes("🙂")

    #expect(decoder.feed(Array(smiley[0..<2])) == [])

    let events = decoder.feed(Array(smiley[2...]))

    #expect(events == [.key(KeyInput(key: .character("🙂")))])
}

// MARK: - Escape Disambiguation

@Test func loneEscapeIsHeldThenFlushed() {
    var decoder = ANSIInputDecoder()

    #expect(decoder.feed([esc]) == [])
    #expect(decoder.hasPendingEscape)

    let events = decoder.flushPending()

    #expect(events == [.key(KeyInput(key: .escape))])
    #expect(!decoder.hasPendingEscape)
}

@Test func escapeFollowedBySequenceIsNotTheEscapeKey() {
    var decoder = ANSIInputDecoder()

    #expect(decoder.feed([esc]) == [])

    let events = decoder.feed(bytes("[A"))

    #expect(events == [.key(KeyInput(key: .up))])
}

@Test func altPrintableDecodesWithAltModifier() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed([esc, UInt8(ascii: "f")])

    #expect(events == [.key(KeyInput(key: .character("f"), modifiers: .alt))])
}

// MARK: - CSI Keys

@Test func decodesArrowKeys() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[D"))

    #expect(events == [
        .key(KeyInput(key: .up)),
        .key(KeyInput(key: .down)),
        .key(KeyInput(key: .right)),
        .key(KeyInput(key: .left)),
    ])
}

@Test func decodesArrowWithModifiers() {
    var decoder = ANSIInputDecoder()

    // CSI 1;5C = Ctrl+Right; CSI 1;2A = Shift+Up; CSI 1;3D = Alt+Left.
    let events = decoder.feed(bytes("\u{1B}[1;5C\u{1B}[1;2A\u{1B}[1;3D"))

    #expect(events == [
        .key(KeyInput(key: .right, modifiers: .control)),
        .key(KeyInput(key: .up, modifiers: .shift)),
        .key(KeyInput(key: .left, modifiers: .alt)),
    ])
}

@Test func decodesNavigationAndTildeKeys() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("\u{1B}[H\u{1B}[F\u{1B}[3~\u{1B}[5~\u{1B}[6~"))

    #expect(events == [
        .key(KeyInput(key: .home)),
        .key(KeyInput(key: .end)),
        .key(KeyInput(key: .delete)),
        .key(KeyInput(key: .pageUp)),
        .key(KeyInput(key: .pageDown)),
    ])
}

@Test func decodesFunctionKeysInAllForms() {
    var decoder = ANSIInputDecoder()

    // SS3 F1, tilde F5, tilde F12.
    let events = decoder.feed(bytes("\u{1B}OP\u{1B}[15~\u{1B}[24~"))

    #expect(events == [
        .key(KeyInput(key: .function(1))),
        .key(KeyInput(key: .function(5))),
        .key(KeyInput(key: .function(12))),
    ])
}

@Test func decodesShiftTab() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("\u{1B}[Z"))

    #expect(events == [.key(KeyInput(key: .tab, modifiers: .shift))])
}

@Test func csiSplitAcrossChunksStillDecodes() {
    var decoder = ANSIInputDecoder()

    #expect(decoder.feed([esc, UInt8(ascii: "[")]) == [])
    #expect(decoder.feed(bytes("1;5")) == [])

    let events = decoder.feed(bytes("C"))

    #expect(events == [.key(KeyInput(key: .right, modifiers: .control))])
}

@Test func unknownCSISequenceIsDropped() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("\u{1B}[99q") + bytes("x"))

    #expect(events == [.key(KeyInput(key: .character("x")))])
}

// MARK: - SGR Mouse

@Test func decodesMousePressAndRelease() {
    var decoder = ANSIInputDecoder()

    // Left press at (5, 3) 1-based -> (4, 2); left release same spot.
    let events = decoder.feed(bytes("\u{1B}[<0;5;3M\u{1B}[<0;5;3m"))

    #expect(events == [
        .mouse(MouseInput(position: Point(x: 4, y: 2), action: .press, button: .left)),
        .mouse(MouseInput(position: Point(x: 4, y: 2), action: .release, button: .left)),
    ])
}

@Test func decodesRightAndMiddleButtons() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("\u{1B}[<2;1;1M\u{1B}[<1;1;1M"))

    #expect(events == [
        .mouse(MouseInput(position: .zero, action: .press, button: .right)),
        .mouse(MouseInput(position: .zero, action: .press, button: .middle)),
    ])
}

@Test func decodesDragAndMove() {
    var decoder = ANSIInputDecoder()

    // 32 = left drag; 35 = motion with no button.
    let events = decoder.feed(bytes("\u{1B}[<32;2;2M\u{1B}[<35;3;3M"))

    #expect(events == [
        .mouse(MouseInput(position: Point(x: 1, y: 1), action: .drag, button: .left)),
        .mouse(MouseInput(position: Point(x: 2, y: 2), action: .move, button: .none)),
    ])
}

@Test func decodesScrollWheel() {
    var decoder = ANSIInputDecoder()

    let events = decoder.feed(bytes("\u{1B}[<64;1;1M\u{1B}[<65;1;1M"))

    #expect(events == [
        .mouse(MouseInput(position: .zero, action: .scrollUp)),
        .mouse(MouseInput(position: .zero, action: .scrollDown)),
    ])
}

@Test func decodesMouseModifiers() {
    var decoder = ANSIInputDecoder()

    // 0 + ctrl(16) = 16: ctrl+left press.
    let events = decoder.feed(bytes("\u{1B}[<16;1;1M"))

    #expect(events == [
        .mouse(MouseInput(position: .zero, action: .press, button: .left, modifiers: .control)),
    ])
}

// MARK: - Driver Guards

@Test func ansiDriverRefusesNonTerminal() async throws {
    // Under `swift test` stdin/stdout is typically not a TTY; when it is,
    // this test would enter raw mode, so only assert in the non-TTY case.
    guard isatty(0) == 0 || isatty(1) == 0 else {
        return
    }

    let driver = ANSIDriver()

    await #expect(throws: ANSIDriver.DriverError.notATerminal) {
        try await driver.begin()
    }

    // end() after failed begin() is safe (unconditional cleanup contract).
    await driver.end()
}

// MARK: - Control strings

/// A terminal's replies to the *application driving it* must never reach the
/// application's key handling.
@Suite struct ControlStringDecodingTests {

    /// Feeds a string as bytes and returns what the decoder made of it.
    private func decode(_ text: String) -> [TerminalInput] {
        var decoder = ANSIInputDecoder()
        return decoder.feed(Array(text.utf8))
    }

    @Test("a VTG frame acknowledgement produces no input at all")
    func apcRepliesAreSwallowed() {
        // Exactly the reply that was being typed into the focused text field.
        let events = decode("\u{1b}_VTG;frameStarted,id=tuikit-chrome,timeout=250\u{1b}\\")

        #expect(events.isEmpty)
    }

    @Test("typing after a control string still works")
    func inputResumesAfterAControlString() {
        let events = decode("\u{1b}_VTG;ok\u{1b}\\hi")

        #expect(events.count == 2)
        #expect(events.first == .key(KeyInput(key: .character("h"))))
        #expect(events.last == .key(KeyInput(key: .character("i"))))
    }

    @Test("OSC may be terminated by BEL, as xterm allows")
    func oscAcceptsBEL() {
        let events = decode("\u{1b}]0;a window title\u{07}x")

        #expect(events == [.key(KeyInput(key: .character("x")))])
    }

    @Test("an ESC inside the payload is payload, not a terminator")
    func anEscapeInsideThePayloadDoesNotEndIt() {
        let events = decode("\u{1b}_a\u{1b}b\u{1b}\\z")

        #expect(events == [.key(KeyInput(key: .character("z")))])
    }

    @Test("DCS, PM and SOS are swallowed the same way")
    func theOtherIntroducersAreSwallowedToo() {
        for introducer in ["P", "^", "X"] {
            let events = decode("\u{1b}\(introducer)payload;here\u{1b}\\q")

            #expect(events == [.key(KeyInput(key: .character("q")))],
                    "ESC \(introducer) leaked its payload")
        }
    }

    @Test("a control string split across reads is still swallowed")
    func aSplitControlStringIsSwallowed() {
        var decoder = ANSIInputDecoder()
        var events = decoder.feed(Array("\u{1b}_VTG;frame".utf8))
        events += decoder.feed(Array("Started\u{1b}".utf8))
        events += decoder.feed(Array("\\k".utf8))

        #expect(events == [.key(KeyInput(key: .character("k")))])
    }

    @Test("a stray continuation byte is dropped, not treated as a C1 control")
    func strayContinuationBytesDoNotStartAControlString() {
        var decoder = ANSIInputDecoder()
        let events = decoder.feed([0x9F, UInt8(ascii: "a")])

        // If 0x9F started a control string, the "a" would vanish too.
        #expect(events == [.key(KeyInput(key: .character("a")))])
    }

    @Test("a control string whose terminator never comes cannot deafen the keyboard forever")
    func aTerminatorlessControlStringSelfHealsAtTheCap() {
        // The lockup shape: an APC opener whose ST is lost (dropped byte,
        // terminal dying mid-reply, reordered chunks). Without a cap the
        // decoder swallows every keystroke for the rest of the session —
        // an app that renders but cannot be quit.
        var decoder = ANSIInputDecoder()
        var events = decoder.feed(Array("\u{1b}_VTG;frameStarted".utf8))

        let flood = [UInt8](repeating: UInt8(ascii: "x"),
                            count: ANSIInputDecoder.controlStringCap + 1)
        events += decoder.feed(flood)

        // Payload swallows up to the cap; whatever spills past it types as
        // garbage — the accepted price, a fraction of the flood at most.
        #expect(events.allSatisfy { $0 == .key(KeyInput(key: .character("x"))) })
        #expect(events.count < 32, "almost everything should still be swallowed")

        // Past the cap the decoder is idle again: keys decode.
        let after = decoder.feed(Array("q".utf8))
        #expect(after == [.key(KeyInput(key: .character("q")))],
                "the keyboard must come back after the cap")
    }

    @Test("a real-sized control string is nowhere near the cap")
    func ordinaryRepliesAreUntouchedByTheCap() {
        var decoder = ANSIInputDecoder()
        let payload = String(repeating: "p", count: 2048)
        let events = decoder.feed(Array("\u{1b}_VTG;\(payload)\u{1b}\\z".utf8))

        #expect(events == [.key(KeyInput(key: .character("z")))],
                "a large-but-legal reply still terminates normally")
    }
}
