import XCTest
@testable import CollationKit

// MARK: - Tokeniser: characters above U+FFFF, quotes, apostrophes and dashes (release 1 review, B4 and B5)
//
// B4: the tokeniser built each scalar from a single UTF-16 unit, so every character outside the Basic Multilingual
// Plane (rare CJK, historic scripts, mathematical letters, emoji) was silently dropped and a change to one reported
// no variant. B5: `'`, `’` and `-` counted as word characters anywhere, so a leading or trailing quote and a dash
// became part of a word, and straight vs typographic apostrophes were different words; the GB/US quotation styles
// and `--` vs `—` all surfaced as SUBSTANTIVE variants.

final class TokenizerUnicodeTests: XCTestCase {

    private func collate(_ a: String, _ b: String, _ normalizer: Normalizer = .substantive,
                         recordPunctuation: Bool = false) -> CollationResult {
        Collation.collate(base: Witness(id: "A", text: a), compared: Witness(id: "B", text: b),
                          normalizer: normalizer, recordPunctuation: recordPunctuation)
    }

    private func words(_ text: String, _ normalizer: Normalizer = .substantive) -> [String] {
        Tokenizer.tokenize(text, with: normalizer).filter { $0.kind == .word }.map(\.surface)
    }

    // MARK: B4 — supplementary-plane characters

    func testSupplementaryPlaneLettersAreWords() {
        XCTAssertEqual(words("the 𠀀 stone and 𝔄 here"), ["the", "𠀀", "stone", "and", "𝔄", "here"])
        XCTAssertEqual(words("b𝐀c"), ["b𝐀c"], "a letter above U+FFFF does not split its word")
        XCTAssertEqual(words("𐌰𐌱𐌲 gothic"), ["𐌰𐌱𐌲", "gothic"])
    }

    func testAChangeToASupplementaryPlaneLetterIsReported() {
        let r = collate("the 𠀀 stone and 𝔄 here", "the 𠀁 stone and 𝔅 here")
        XCTAssertEqual(r.variations.filter { $0.type == .substitution }.map(\.baseReading), ["𠀀", "𝔄"])
    }

    func testCharacterRangesStayCorrectAroundSurrogatePairs() {
        let text = "a 😀 𝔄bc d"
        let toks = Tokenizer.tokenize(text, with: .diplomatic)
        let ns = text as NSString
        for t in toks {
            XCTAssertEqual(ns.substring(with: NSRange(location: t.range.lowerBound, length: t.range.count)), t.surface)
        }
        XCTAssertEqual(toks.map(\.surface), ["a", "😀", "𝔄bc", "d"])
    }

    func testEmojiAreSymbolsFoldedSubstantivelyButRecordedDiplomatically() {
        XCTAssertTrue(collate("a 😀 b", "a 😎 b").variations.isEmpty, "a symbol is punctuation-class in substantive mode")
        XCTAssertFalse(collate("a 😀 b", "a 😎 b", .diplomatic).variations.isEmpty, "diplomatic mode records it")
    }

    // MARK: B5 — quotes, apostrophes, dashes

    func testQuotationStylesAreNotSubstantive() {
        // British single quotes vs American double quotes: the same words.
        XCTAssertEqual(words("'Hello,' she said."), ["Hello", "she", "said"])
        XCTAssertTrue(collate("'Hello,' she said to me.", "\"Hello,\" she said to me.").variations.isEmpty)
    }

    func testTypographicApostrophesFoldSubstantivelyOnly() {
        XCTAssertTrue(collate("don't go", "don’t go").variations.isEmpty)
        XCTAssertEqual(collate("don't go", "don’t go", .diplomatic).variations.count, 1, "diplomatic records it")
        XCTAssertEqual(words("don’t"), ["don’t"], "an interior apostrophe stays inside the word")
    }

    func testDashesArePunctuation() {
        XCTAssertTrue(collate("He paused -- then went", "He paused — then went").variations.isEmpty)
        XCTAssertTrue(collate("He paused--then went", "He paused — then went").variations.isEmpty)
        XCTAssertEqual(words("paused--then"), ["paused", "then"])
    }

    func testLeadingAndTrailingApostrophesArePunctuation() {
        XCTAssertEqual(words("'tis the dogs' bones"), ["tis", "the", "dogs", "bones"])
    }
}
