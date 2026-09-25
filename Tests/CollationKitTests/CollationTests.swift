import XCTest
@testable import CollationKit

// Stage-3/facade tests: the end-to-end pairwise `Collation.collate` over witnesses, asserting the typed
// apparatus (insertion / deletion / substitution / transposition) and the cross-page flag.

final class CollationTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    func testPureInsertionIsReportedAsInsertion() {
        let r = Collation.collate(base: w("A", "the cat sat"), compared: w("B", "the black cat sat"))
        XCTAssertEqual(r.insertions, 1)
        XCTAssertEqual(r.deletions, 0)
        XCTAssertEqual(r.substitutions, 0)
        XCTAssertEqual(r.variations.first { $0.type == .insertion }?.comparedReading, "black")
    }

    func testPureDeletionIsReportedAsDeletion() {
        let r = Collation.collate(base: w("A", "the black cat sat"), compared: w("B", "the cat sat"))
        XCTAssertEqual(r.deletions, 1)
        XCTAssertEqual(r.variations.first { $0.type == .deletion }?.baseReading, "black")
    }

    func testRewordedClauseIsSubstitutionNotDeleteInsert() {
        // A reworded phrase should read as ONE substitution span, the apparatus a scholar wants — not a
        // delete block followed by an insert block (the diff failure mode).
        let r = Collation.collate(base: w("A", "she was very happy indeed"),
                                  compared: w("B", "she was quite content indeed"))
        XCTAssertEqual(r.substitutions, 1)
        let sub = r.variations.first { $0.type == .substitution }
        XCTAssertEqual(sub?.baseReading, "very happy")
        XCTAssertEqual(sub?.comparedReading, "quite content")
    }

    func testAccidentalOnlyChangeIsSuppressedUnderSubstantiveNormalization() {
        // Capitalization + punctuation only: no substantive variation.
        let r = Collation.collate(base: w("A", "the End."), compared: w("B", "the end"),
                                  normalizer: .substantive)
        XCTAssertTrue(r.variations.isEmpty, "accidentals are folded away by substantive normalization")
    }

    func testAccidentalSurfacesUnderDiplomaticNormalization() {
        // The same pair, compared diplomatically, DOES record the accidental (capital E → e).
        let r = Collation.collate(base: w("A", "the End of days"), compared: w("B", "the end of days"),
                                  normalizer: .diplomatic)
        XCTAssertEqual(r.substitutions, 1)
    }

    func testGBUSSpellingNotCountedAsSubstantiveVariant() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        let r = Collation.collate(base: w("GB", "the colour of the harbour"),
                                  compared: w("US", "the color of the harbor"),
                                  normalizer: norm)
        XCTAssertTrue(r.variations.isEmpty, "GB/US spelling differences fold to the same reading")
    }
}
