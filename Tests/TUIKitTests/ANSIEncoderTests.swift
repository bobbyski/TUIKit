import Testing
@testable import TUIKit

private let esc = "\u{1B}"

@Test func defaultStyleEncodesAsPlainReset() {
    #expect(ANSIEncoder.sequence(for: .default) == "\(esc)[0m")
}

@Test func flagsEncodeTheirSGRCodes() {
    let style = CellStyle(flags: [.bold, .underline])

    #expect(ANSIEncoder.sequence(for: style) == "\(esc)[0;1;4m")
}

@Test func namedColorsEncodeForegroundAndBackground() {
    let style = CellStyle(foreground: .named(.red), background: .named(.brightWhite))

    #expect(ANSIEncoder.sequence(for: style) == "\(esc)[0;31;107m")
}

@Test func paletteAndRGBColorsEncodeExtendedSequences() {
    let palette = CellStyle(foreground: .palette(208))
    let rgb = CellStyle(background: .rgb(red: 1, green: 2, blue: 3))

    #expect(ANSIEncoder.sequence(for: palette) == "\(esc)[0;38;5;208m")
    #expect(ANSIEncoder.sequence(for: rgb) == "\(esc)[0;48;2;1;2;3m")
}

@Test func encodedLinesShareRunsAndEndWithReset() {
    var buffer = CellBuffer(size: Size(width: 4, height: 1))
    let bold = CellStyle(flags: .bold)

    buffer.write("ab", at: .zero, style: bold)
    buffer.write("cd", at: Point(x: 2, y: 0))

    let lines = ANSIEncoder.encode(buffer)

    #expect(lines.count == 1)
    // One sequence for the bold run, one for the default run, one reset.
    #expect(lines[0] == "\(esc)[0;1mab\(esc)[0mcd\(esc)[0m")
}

@Test func plainBufferEncodesWithSingleLeadingSequence() {
    var buffer = CellBuffer(size: Size(width: 3, height: 2))
    buffer.write("hi", at: .zero)

    let lines = ANSIEncoder.encode(buffer)

    #expect(lines == ["\(esc)[0mhi \(esc)[0m", "\(esc)[0m   \(esc)[0m"])
}
