import XCTest
@testable import CollationKit

// MARK: - no_collate regions (release 1 review, blocker B6)
//
// Three defects let excluded matter leak into the collation: the documented two-comment form closed at its own
// opener's `-->`; a page-break comment inside a one-comment region ended the region at the inner comment's `-->`; and
// a `---` or form-feed page break inside a region moved the scanner back into the region after it had jumped past.
// The invariant pinned here: no token's range intersects a no_collate region, and markers inside one count nothing.

final class NoCollateRegionTests: XCTestCase {

    private func words(_ text: String) -> [String] {
        Tokenizer.tokenize(text, with: .substantive).filter { $0.kind == .word }.map(\.surface)
    }

    private func assertNoTokenInsideRegions(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let regions = Tokenizer.noCollateRanges(in: text)
        XCTAssertFalse(regions.isEmpty, "the text has a region", file: file, line: line)
        for token in Tokenizer.tokenize(text, with: .diplomatic) {
            XCTAssertFalse(regions.contains { $0.overlaps(token.range) },
                           "token '\(token.surface)' lies inside an excluded region", file: file, line: line)
        }
    }

    func testTwoCommentFormExcludesTheMatterBetween() {
        let text = "<!-- no_collate -->\nPreface by the translator here\n<!-- /no_collate -->\nthe cat sat on the mat\n"
        XCTAssertEqual(words(text), ["the", "cat", "sat", "on", "the", "mat"])
        assertNoTokenInsideRegions(text)
    }

    func testANestedPageBreakCommentDoesNotEndTheRegion() {
        let text = "<!-- no_collate\nPreface page one\n<!-- page break -->\nPreface page two words\n-->\nthe cat sat on the mat\n"
        XCTAssertEqual(words(text), ["the", "cat", "sat", "on", "the", "mat"])
        assertNoTokenInsideRegions(text)
        XCTAssertEqual(Tokenizer.tokenize(text, with: .substantive).first?.page, 0,
                       "a page break inside the excluded matter is not counted")
    }

    func testAThematicBreakInsideTheRegionDoesNotRewindTheScanner() {
        for marker in ["---", "\u{0C}"] {
            let text = "<!-- no_collate\nfront matter alpha\n\(marker)\nmore front matter beta\n-->\nthe cat sat on the mat\n"
            XCTAssertEqual(words(text), ["the", "cat", "sat", "on", "the", "mat"], "marker \(marker.debugDescription)")
            assertNoTokenInsideRegions(text)
            XCTAssertEqual(Tokenizer.tokenize(text, with: .substantive).first?.page, 0)
        }
    }

    func testPageBreaksOutsideRegionsStillCount() {
        let text = "one\n<!-- page break -->\ntwo\n<!-- no_collate\nx\n<!-- page break -->\ny\n-->\nthree\n<!-- page break -->\nfour\n"
        let pages = Dictionary(uniqueKeysWithValues: Tokenizer.tokenize(text, with: .substantive)
            .filter { $0.kind == .word }.map { ($0.surface, $0.page) })
        XCTAssertEqual(pages, ["one": 0, "two": 1, "three": 1, "four": 2])
    }

    func testOneCommentFormAcceptsTheExplicitEndTagAndRunsToEndWhenUnclosed() {
        XCTAssertEqual(words("<!-- no_collate\nfront\n<!-- /no_collate -->\nbody text"), ["body", "text"])
        XCTAssertEqual(words("body text\n<!-- no_collate\nback matter to the end"), ["body", "text"])
        XCTAssertEqual(words("body\n<!-- no_collate -->\nback matter, never closed"), ["body"])
    }
}
