import XCTest
@testable import CollationKit

// Tests for the LOCATING layer: page / line / word / char-range on each variation, and the located report.
// This is what lets a host app tell the user WHERE a change is — visually (charRange), by word, line, or page.

final class LocationTests: XCTestCase {

    private func w(_ id: String, _ t: String) -> Witness { Witness(id: id, text: t) }

    func testTokenLineIsPerPageAndTextOnlyWordIsPerLine() {
        // Line numbering is PER PAGE and counts only TEXT lines (the blank lines and the page-break marker
        // line are NOT numbered, as in a printed edition). Word position is PER LINE.
        let toks = Tokenizer.tokenize("one two\nthree four\n\n<!-- page break -->\n\nfive six", with: .substantive)
        let five = toks.first { $0.surface == "five" }
        XCTAssertEqual(five?.page, 1, "after the page break, page is 1")
        XCTAssertEqual(five?.line, 0, "'five' is on the FIRST text line of page 1 (line resets per page)")
        XCTAssertEqual(five?.wordIndex, 0, "'five' is the first word ON ITS LINE")
        // Page 0: "three four" is the 2nd text line of the page; "four" is the 2nd word on it.
        let four = toks.first { $0.surface == "four" }
        XCTAssertEqual(four?.page, 0)
        XCTAssertEqual(four?.line, 1, "'four' is on the 2nd text line of page 0")
        XCTAssertEqual(four?.wordIndex, 1, "'four' is the 2nd word on its line")
    }

    func testSingleWordSubstitutionCitesAWordPosition() {
        let r = Collation.collate(base: w("A", "the quick brown fox"), compared: w("B", "the quick red fox"))
        let sub = r.variations.first { $0.type == .substitution }!
        XCTAssertTrue(sub.baseLocation!.isSingleWord)
        XCTAssertEqual(sub.baseLocation?.firstWord, 2, "'brown' is the 3rd word on its line (0-based 2)")
        XCTAssertEqual(sub.baseReading, "brown")
        // A single-word change cites a word POSITION.
        XCTAssertEqual(sub.baseLocation?.human, "p.1 · line 1 · word 3")
    }

    func testMultiWordSubstitutionCitesAWordRange() {
        let r = Collation.collate(base: w("A", "she was very happy indeed"),
                                  compared: w("B", "she was quite content indeed"))
        let sub = r.variations.first { $0.type == .substitution }!
        XCTAssertFalse(sub.baseLocation!.isSingleWord)
        XCTAssertEqual(sub.baseLocation?.firstWord, 2)
        XCTAssertEqual(sub.baseLocation?.lastWord, 3)
        // A multi-word change cites a word RANGE on the line.
        XCTAssertEqual(sub.baseLocation?.human, "p.1 · line 1 · words 3–4")
    }

    func testLocationCharRangeCoversTheReadingForHighlighting() {
        let base = "the quick brown fox"
        let r = Collation.collate(base: w("A", base), compared: w("B", "the quick red fox"))
        let sub = r.variations.first { $0.type == .substitution }!
        let cr = sub.baseLocation!.charRange
        let ns = base as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: cr.lowerBound, length: cr.count)), "brown",
                       "the char range highlights exactly the changed word")
    }

    func testMultiWordSubstitutionRangeSpansTheWholeReading() {
        let base = "she was very happy indeed"
        let r = Collation.collate(base: w("A", base), compared: w("B", "she was quite content indeed"))
        let sub = r.variations.first { $0.type == .substitution }!
        let cr = sub.baseLocation!.charRange
        let ns = base as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: cr.lowerBound, length: cr.count)), "very happy")
    }

    func testDeletionHasNoComparedLocation() {
        let r = Collation.collate(base: w("A", "the black cat"), compared: w("B", "the cat"))
        let del = r.variations.first { $0.type == .deletion }!
        XCTAssertNotNil(del.baseLocation)
        XCTAssertNil(del.comparedLocation, "a deletion has no location in the compared witness")
    }

    func testLocatedReportNamesTypeAndPlace() {
        let r = Collation.collate(base: w("MS", "the cold wind blew"), compared: w("TS", "the bitter wind blew"))
        let text = Report.located(r)
        XCTAssertTrue(text.contains("SUBSTITUTION"))
        XCTAssertTrue(text.contains("“cold”"))
        XCTAssertTrue(text.contains("“bitter”"))
        XCTAssertTrue(text.contains("word 2"), "the report cites the word position; got:\n\(text)")
    }

    func testMultiLineReadingCitesALineRange() {
        // A reading that runs across a line break cites "lines X–Y". Here the base puts "happy indeed" on
        // two lines; the substitution spans them.
        let r = Collation.collate(base: w("A", "she was very happy\nindeed today"),
                                  compared: w("B", "she was quite content\nfor now today"))
        let sub = r.variations.first { $0.type == .substitution }!
        XCTAssertEqual(sub.baseLocation?.line, 0)
        XCTAssertEqual(sub.baseLocation?.endLine, 1)
        XCTAssertTrue(sub.baseLocation!.human.contains("lines 1–2"),
                      "a reading across two lines cites a line range; got: \(sub.baseLocation!.human)")
    }

    func testReportFlagsCrossPageMove() {
        // Use the built-in sample's TS→PR move, which crosses a page.
        let ts = Samples.sixEditions[1], pr = Samples.sixEditions[2]
        let text = Report.located(Collation.collate(base: ts, compared: pr))
        XCTAssertTrue(text.contains("TRANSPOSITION"))
        XCTAssertTrue(text.contains("ACROSS PAGES"))
    }
}
