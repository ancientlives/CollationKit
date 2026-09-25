import XCTest
@testable import CollationKit

// MARK: - Punctuation as a first-class accidental (diplomatic mode, BACKLOG B6b)
//
// By default the engine folds punctuation before alignment, so punctuation-only differences (comma drops,
// `:`→`;`, `—`→space) are invisible — correct for a *substantive* apparatus, but a gap for a *diplomatic*
// transcription where punctuation is editorially significant (the Frankenstein 1818→1831 case: almost every
// real change there was punctuation, and even `--accidentals` reported nothing). `recordPunctuation` adds an
// opt-in OVERLAY: punctuation between aligned words is compared and differences reported as `.variantSpelling`
// accidentals. It is a pure overlay — alignment and the substantive apparatus are byte-identical with it off.

final class PunctuationTests: XCTestCase {

    private func w(_ id: String, _ t: String) -> Witness { Witness(id: id, text: t) }

    func testPunctuationOnlyDifferenceIsInvisibleByDefault() {
        // Same words, different punctuation → substantive collation reports nothing (the default).
        let r = Collation.collate(base: w("A", "she slept indeed, but woke"),
                                  compared: w("B", "she slept indeed but woke"))
        XCTAssertTrue(r.variations.isEmpty, "punctuation-only change must not surface in substantive mode")
    }

    func testRecordPunctuationSurfacesACommaDrop() {
        let r = Collation.collate(base: w("A", "she slept indeed, but woke"),
                                  compared: w("B", "she slept indeed but woke"),
                                  recordPunctuation: true)
        let acc = r.variations.filter { $0.type == .variantSpelling }
        XCTAssertEqual(acc.count, 1, "the dropped comma should surface as one accidental")
        XCTAssertTrue(acc.first!.baseReading.contains(","), "base had the comma")
        XCTAssertEqual(acc.first!.comparedReading, "∅", "compared dropped it")
    }

    func testRecordPunctuationSurfacesColonToSemicolon() {
        let r = Collation.collate(base: w("A", "it was in vain: it was dark"),
                                  compared: w("B", "it was in vain; it was dark"),
                                  recordPunctuation: true)
        let acc = r.variations.filter { $0.type == .variantSpelling }
        XCTAssertEqual(acc.count, 1)
        XCTAssertEqual(acc.first?.baseReading, ":")
        XCTAssertEqual(acc.first?.comparedReading, ";")
    }

    func testIdenticalPunctuationIsNotReported() {
        let r = Collation.collate(base: w("A", "one, two, three."),
                                  compared: w("B", "one, two, three."),
                                  recordPunctuation: true)
        XCTAssertTrue(r.variations.isEmpty, "identical punctuation must report nothing")
    }

    func testRecordPunctuationDoesNotAffectSubstantiveVariants() {
        // A real substantive change PLUS a punctuation change: the substitution is reported either way; the
        // punctuation accidental only appears with the overlay on. Crucially the substantive set is identical.
        let base = w("A", "the quick, brown fox")
        let comp = w("B", "the quick red fox")
        let sub = Collation.collate(base: base, compared: comp)
        let dip = Collation.collate(base: base, compared: comp, recordPunctuation: true)
        let subSubstantive = sub.variations.filter { $0.type != .variantSpelling }
        let dipSubstantive = dip.variations.filter { $0.type != .variantSpelling }
        XCTAssertEqual(subSubstantive, dipSubstantive, "the substantive apparatus must be unchanged by the overlay")
        XCTAssertEqual(sub.substitutions, 1)
        XCTAssertTrue(dip.variations.contains { $0.type == .variantSpelling }, "the dropped comma surfaces with the overlay")
    }

    func testRecordPunctuationIsDeterministic() {
        let a = w("A", "alpha, beta; gamma: delta")
        let b = w("B", "alpha beta, gamma; delta")
        XCTAssertEqual(Collation.collate(base: a, compared: b, recordPunctuation: true),
                       Collation.collate(base: a, compared: b, recordPunctuation: true))
    }

    func testFrankensteinPassageSurfacesPunctuationWithOverlay() {
        // The real motivating case: the 1818/1831 creation-scene witnesses differ almost entirely in
        // punctuation. Substantively they are identical (case 17 → no variants); with the overlay the
        // punctuation differences become visible — the diplomatic view the study said was missing.
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/conformance/cases/17-frankenstein-creation-scene")
        guard let t1818 = try? String(contentsOf: dir.appendingPathComponent("1818.txt"), encoding: .utf8),
              let t1831 = try? String(contentsOf: dir.appendingPathComponent("1831.txt"), encoding: .utf8) else {
            return XCTFail("could not read the Frankenstein corpus case")
        }
        let sub = Collation.collate(base: w("1818", t1818), compared: w("1831", t1831))
        XCTAssertTrue(sub.variations.isEmpty, "substantively identical (the B6 hyphen fix)")
        let dip = Collation.collate(base: w("1818", t1818), compared: w("1831", t1831), recordPunctuation: true)
        XCTAssertGreaterThan(dip.variations.filter { $0.type == .variantSpelling }.count, 0,
            "the diplomatic overlay reveals the punctuation changes the substantive view (correctly) hides")
    }
}
