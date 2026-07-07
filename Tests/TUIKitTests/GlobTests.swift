import Testing
@testable import TUIKit

@Test func globStarMatchesExtensions() {
    #expect(Glob.matches("Report.txt", pattern: "*.txt"))
    #expect(Glob.matches("archive.tar.gz", pattern: "*.gz"))
    #expect(!Glob.matches("Report.md", pattern: "*.txt"))
    #expect(Glob.matches("anything", pattern: "*"))
    #expect(Glob.matches("anything", pattern: ""), "an empty pattern matches all")
}

@Test func globQuestionMarkMatchesOneCharacter() {
    #expect(Glob.matches("a.c", pattern: "?.c"))
    #expect(!Glob.matches("ab.c", pattern: "?.c"))
    #expect(Glob.matches("file1.log", pattern: "file?.log"))
}

@Test func globIsCaseInsensitive() {
    #expect(Glob.matches("NOTES.TXT", pattern: "*.txt"))
    #expect(Glob.matches("notes.txt", pattern: "*.TXT"))
}

@Test func globBraceGroupMatchesAlternatives() {
    #expect(Glob.matches("readme.md", pattern: "*.{txt,md}"))
    #expect(Glob.matches("notes.txt", pattern: "*.{txt,md}"))
    #expect(!Glob.matches("image.png", pattern: "*.{txt,md}"))
    #expect(Glob.matches("Makefile", pattern: "{Makefile,*.mk}"))
    #expect(Glob.matches("build.mk", pattern: "{Makefile,*.mk}"))
}

@Test func globMatchesAnyAcrossPatterns() {
    #expect(Glob.matchesAny("main.swift", patterns: ["*.h", "*.swift"]))
    #expect(!Glob.matchesAny("main.o", patterns: ["*.h", "*.swift"]))
    #expect(Glob.matchesAny("whatever", patterns: []), "no patterns matches all")
}

@Test func globAnchorsWholeName() {
    // A pattern matches the entire name, not a substring.
    #expect(!Glob.matches("notes.txt.bak", pattern: "*.txt"))
    #expect(Glob.matches("notes.txt.bak", pattern: "*.txt.bak"))
    #expect(Glob.matches("notes.txt.bak", pattern: "*.bak"))
}
