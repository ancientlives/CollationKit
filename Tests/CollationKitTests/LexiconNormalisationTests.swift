import XCTest
@testable import CollationKit

// MARK: - Lexicon normalisation and file parsing (release 1 review, blocker B7)
//
// Token keys are normalised (under `.substantive`, `année` → `annee`), but lexicon forms were only lower-cased, so
// an entry with a diacritic never matched: the documented `année, year` example did nothing, and most French
// entries were silently inert. And the parser split on the `"\n"` Character, which does not match the `"\r\n"`
// grapheme, so a CRLF lexicon file was read as one line. The collation entry points now re-key the lexicon with the
// run's normaliser (`TranslationLexicon.normalized(with:)`), and the parser splits on every newline style.

final class LexiconNormalisationTests: XCTestCase {

    private func collate(_ a: String, _ b: String, lexicon: TranslationLexicon,
                         normalizer: Normalizer = .substantive) -> CollationResult {
        Collation.collate(base: Witness(id: "fr", text: a), compared: Witness(id: "en", text: b),
                          normalizer: normalizer, lexicon: lexicon)
    }

    func testAnAccentedEntryMatchesUnderTheDefaultNormaliser() {
        let lexicon = TranslationLexicon.parse("phénomène, phenomenon\nannée, year\n")
        XCTAssertTrue(collate("le phénomène était grand", "le phenomenon était grand", lexicon: lexicon).variations.isEmpty)
        XCTAssertTrue(collate("une année passe", "une year passe", lexicon: lexicon).variations.isEmpty)
    }

    func testAnAccentedEntryMatchesDiplomaticallyToo() {
        let lexicon = TranslationLexicon.parse("année, year\n")
        XCTAssertTrue(collate("une année passe", "une year passe", lexicon: lexicon, normalizer: .diplomatic)
            .variations.isEmpty)
    }

    func testNormalisedKeysFollowTheRunsNormaliser() {
        let lexicon = TranslationLexicon(groups: [["Année", "year"]])
        XCTAssertEqual(lexicon.normalized(with: .substantive).pivot("annee"),
                       lexicon.normalized(with: .substantive).pivot("year"))
        XCTAssertEqual(lexicon.normalized(with: .diplomatic).pivot("année"),
                       lexicon.normalized(with: .diplomatic).pivot("year"))
        // Re-keying is idempotent.
        XCTAssertEqual(lexicon.normalized(with: .substantive).normalized(with: .substantive),
                       lexicon.normalized(with: .substantive))
    }

    func testACRLFFileParsesLikeAnLFFile() {
        let lf = TranslationLexicon.parse("annee, year\nmer, sea\n")
        let crlf = TranslationLexicon.parse("annee, year\r\nmer, sea\r\n")
        let cr = TranslationLexicon.parse("annee, year\rmer, sea\r")
        XCTAssertEqual(crlf, lf)
        XCTAssertEqual(cr, lf)
        XCTAssertEqual(crlf.pivot("sea"), "mer")
        XCTAssertEqual(crlf.pivot("year"), "annee")
    }

    func testEqualityIgnoresGroupAndFormOrder() {
        XCTAssertEqual(TranslationLexicon(groups: [["year", "année"], ["sea", "mer"]]),
                       TranslationLexicon(groups: [["mer", "sea"], ["année", "year"]]))
    }
}
