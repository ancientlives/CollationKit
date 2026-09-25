import XCTest
@testable import CollationKit

// Pagination model (source-page vs printed-page citation): line/page numbering is an editorial convention
// the tool is TOLD via `PaginationModel`, not inferred. These pin the three page modes and the two
// line-numbering policies, and that collation citations follow the chosen model.

final class PaginationTests: XCTestCase {

    func testMarkersModelBreaksAtSourceMarkers() {
        // Default: a witness with no markers is one page, lines numbered continuously within it.
        let toks = Tokenizer.tokenize("one two\nthree four\nfive six", with: .substantive)
        XCTAssertTrue(toks.allSatisfy { $0.page == 0 }, "no markers ⇒ single page")
        XCTAssertEqual(toks.first { $0.surface == "five" }?.line, 2, "third text line, page-relative")
    }

    func testLinesPerPageSynthesizesPrintedPages() {
        // A uniform printed page of 2 text lines: line 3 should land on page 1, line 1 of that page.
        let text = "l1 a\nl2 b\nl3 c\nl4 d\nl5 e"
        let toks = Tokenizer.tokenize(text, with: .substantive, pagination: .printedPage(linesPerPage: 2))
        let l1 = toks.first { $0.surface == "l1" }!
        let l3 = toks.first { $0.surface == "l3" }!
        let l5 = toks.first { $0.surface == "l5" }!
        XCTAssertEqual([l1.page, l1.line], [0, 0])
        XCTAssertEqual([l3.page, l3.line], [1, 0], "the 3rd text line opens page 1, line 0")
        XCTAssertEqual([l5.page, l5.line], [2, 0], "the 5th text line opens page 2, line 0")
    }

    func testContinuousNumberingDoesNotResetAcrossPages() {
        // Through-numbered: one continuous line sequence, page stays 0, line counts up across the whole text.
        let text = "alpha\nbeta\ngamma\ndelta\nepsilon"
        let toks = Tokenizer.tokenize(text, with: .substantive, pagination: .throughNumbered)
        XCTAssertTrue(toks.allSatisfy { $0.page == 0 }, "through-numbered ⇒ no page resets")
        XCTAssertEqual(toks.first { $0.surface == "epsilon" }?.line, 4, "5th line, numbered 0-based 4")
    }

    func testExplicitPaginationMapMatchesAGivenEdition() {
        // The edition's real page breaks are supplied as source offsets. "third" begins page 1.
        let text = "first second third fourth"
        let thirdOffset = (text as NSString).range(of: "third").location
        let model = PaginationModel(pages: .explicit([0, thirdOffset]))
        let toks = Tokenizer.tokenize(text, with: .substantive, pagination: model)
        XCTAssertEqual(toks.first { $0.surface == "second" }?.page, 0)
        XCTAssertEqual(toks.first { $0.surface == "third" }?.page, 1, "explicit map opens page 1 at 'third'")
        XCTAssertEqual(toks.first { $0.surface == "third" }?.line, 0, "line resets on the new page")
    }

    func testCollationCitationsFollowTheChosenPaginationModel() {
        // The same two witnesses, cited under a printed-page model (3 lines/page), put a later-line change on
        // the expected printed page — the citation reflects the model, not the source's lack of markers.
        let base = Witness(id: "A", text: "l1 w\nl2 w\nl3 w\nl4 old\nl5 w")
        let comp = Witness(id: "B", text: "l1 w\nl2 w\nl3 w\nl4 new\nl5 w")
        let r = Collation.collate(base: base, compared: comp, pagination: .printedPage(linesPerPage: 3))
        let sub = r.variations.first { $0.type == .substitution }!
        XCTAssertEqual(sub.baseLocation?.page, 1, "line 4 falls on the 2nd printed page (3 lines/page)")
        XCTAssertEqual(sub.baseLocation?.line, 0, "and is the first line of that page")
        XCTAssertEqual(sub.baseReading, "old")
    }

    func testDefaultModelMatchesPriorBehaviour() {
        // A regression guard: `.default` reproduces the marker-driven numbering the suite already relies on.
        let toks = Tokenizer.tokenize("a b\n\n<!-- page break -->\n\nc d", with: .substantive,
                                      pagination: .default)
        XCTAssertEqual(toks.first { $0.surface == "c" }?.page, 1)
        XCTAssertEqual(toks.first { $0.surface == "c" }?.line, 0)
    }
}
