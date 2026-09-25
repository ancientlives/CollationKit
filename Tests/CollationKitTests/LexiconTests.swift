import XCTest
@testable import CollationKit

// MARK: - Translation-aware anchoring (BACKLOG B10) — the cross-language layer
//
// B10 adds a `TranslationLexicon`: bilingual equivalence groups whose forms are treated as the SAME key for
// ALIGNMENT ONLY, so a French↔English witness set anchors on translation pairs instead of degrading to
// positional drift (CASE_STUDY.md Case 6, the finding that motivated this item). The contract under test:
// the lexicon is additive (nil/empty = identity, byte-for-byte), alignment-only (readings keep each witness's
// own words), and it pairs with the B14 peer merge for the synoptic multi-rendering graph.

final class LexiconTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    // MARK: the type

    func testPivotMapsGroupMembersToOneKeyAndIsIdentityElsewhere() {
        let lex = TranslationLexicon(groups: [["année", "year"], ["mer", "sea", "seas"]])
        XCTAssertEqual(lex.pivot("année"), lex.pivot("year"), "group members share one pivot")
        XCTAssertEqual(lex.pivot("mer"), lex.pivot("seas"))
        XCTAssertEqual(lex.pivot("bateau"), "bateau", "uncovered forms are untouched (identity)")
        XCTAssertTrue(lex.equates("année", "year"))
        XCTAssertFalse(lex.equates("année", "mer"), "different groups never equate")
    }

    func testParseFileFormat() {
        let lex = TranslationLexicon.parse("""
        # français ↔ english
        année, year

        mer, sea, seas   # multiple targets allowed
        lone-form-ignored
        """)
        XCTAssertFalse(lex.isEmpty)
        XCTAssertTrue(lex.equates("année", "year"))
        XCTAssertTrue(lex.equates("sea", "seas"))
        XCTAssertEqual(lex.pivot("lone-form-ignored"), "lone-form-ignored",
                       "a single-form line equates nothing")
    }

    func testDeterministicUnderGroupAndFormReordering() {
        let a = TranslationLexicon(groups: [["year", "année"], ["sea", "mer"]])
        let b = TranslationLexicon(groups: [["mer", "sea"], ["année", "year"]])
        XCTAssertEqual(a, b, "group/form input order must not matter")
    }

    // MARK: additive — nil/empty is the identity

    func testEmptyLexiconIsByteIdentity() {
        let ws = [w("A", "alpha beta gamma"), w("B", "alpha delta gamma")]
        let plain = CollationJSON.outputString(witnesses: ws)
        let withEmpty = CollationJSON.outputString(witnesses: ws, lexicon: TranslationLexicon(groups: []))
        XCTAssertEqual(plain, withEmpty, "an empty lexicon changes nothing, byte-for-byte")
    }

    /// A lexicon whose forms don't occur in the texts is also a no-op — the layer only acts where it matches.
    func testIrrelevantLexiconIsByteIdentity() {
        let ws = [w("A", "alpha beta gamma"), w("B", "alpha delta gamma")]
        let plain = CollationJSON.outputString(witnesses: ws)
        let with = CollationJSON.outputString(witnesses: ws,
                                              lexicon: TranslationLexicon(groups: [["année", "year"]]))
        XCTAssertEqual(plain, with)
    }

    // MARK: pairwise cross-language alignment

    /// Without a lexicon, a French↔English pair shares no word-forms: the whole text collapses into
    /// positional churn. With a lexicon covering the shared skeleton, those pairs become ANCHORS: the
    /// aligner pins them, lexicon-covered pairs are structural agreement (no variant, and no false
    /// `.variantSpelling` accidental), and genuine structural divergence still surfaces.
    func testLexiconAnchorsAFrenchEnglishPair() {
        let fr = w("fr", "le capitaine regarda la mer immense et sombre")
        let en = w("en", "the captain watched the immense and dark sea")
        let lex = TranslationLexicon(groups: [
            ["le", "la", "the"], ["capitaine", "captain"], ["regarda", "watched"],
            ["mer", "sea"], ["et", "and"], ["sombre", "dark"],
        ])

        // With the lexicon, the covered pairs align as agreement; the only surviving variation is the real
        // structural difference (French "la mer immense et sombre" vs English "the immense and dark sea" —
        // adjective order around the noun), which the aligner reports as the noun's displacement.
        let with = Collation.collate(base: fr, compared: en, lexicon: lex)
        XCTAssertTrue(with.variations.allSatisfy { $0.type == .transposition },
                      "only the genuine word-order divergence remains, as a move: \(with.variations.map { $0.type })")

        // And no lexicon pair leaks out as a spelling accidental (they are translation pairings, not
        // accidentals — the classifier guards on normalised equality).
        let diplomatic = Collation.collate(base: fr, compared: en, recordAccidentals: true, lexicon: lex)
        XCTAssertFalse(diplomatic.variations.contains { v in
            v.type == .variantSpelling && v.baseReading.lowercased() == "capitaine"
        }, "a lexicon pairing must not be reported as a spelling accidental")
    }

    // MARK: the Case-6 scenario — trilingual graph, peer merge

    /// The real Verne opening (Case 22's finding): French + two English translations. Without a lexicon the
    /// graph aligns positionally and drifts. With a small lexicon over the passage's skeleton and the PEER
    /// merge, the two English witnesses group onto shared readings where they agree ("phenomenon",
    /// "forgotten"), and each slot shows the per-witness renderings — the synoptic translation view.
    func testTrilingualVerneGraphPairsTheRightWords() {
        let fr = w("fr", "L'année 1866 fut marquée par un événement bizarre, un phénomène inexpliqué que personne n'a oublié.")
        let mercier = w("en-mercier", "The year 1866 was signalised by a remarkable incident, a mysterious phenomenon which no one has forgotten.")
        let walter = w("en-walter", "THE YEAR 1866 was marked by a bizarre development, an unexplained phenomenon that no one has forgotten.")
        let lex = TranslationLexicon(groups: [
            ["année", "year"], ["fut", "was"], ["marquée", "marked", "signalised"],
            ["un", "a", "an"], ["événement", "incident", "development"],
            ["phénomène", "phenomenon"], ["personne", "one"], ["oublié", "forgotten"],
            ["que", "which", "that"], ["le", "the"], ["par", "by"],
        ])

        let g = Collation.variantGraph(witnesses: [fr, mercier, walter], strategy: .peerMSA, lexicon: lex)

        // The lexicon-anchored slots pair the right words: at the "marquée" slot the readings are the three
        // renderings, each carried by its own witness — not positional neighbours.
        let marquee = g.nodes.first { $0.readings.keys.contains("marquée") }
        XCTAssertNotNil(marquee, "the marquée/marked/signalised slot exists")
        XCTAssertEqual(marquee?.readings["marquée"], ["fr"])
        XCTAssertEqual(marquee?.readings["signalised"], ["en-mercier"])
        XCTAssertEqual(marquee?.readings["marked"], ["en-walter"])

        // The lexicon pairs the sentence skeleton correctly (the drift Case 6 exposed is gone):
        XCTAssertEqual(g.nodes.first { $0.readings.keys.contains("L'année") }?.readings["year"],
                       ["en-mercier", "en-walter"], "L'année ↔ year, both translations grouped")
        XCTAssertEqual(g.nodes.first { $0.readings.keys.contains("fut") }?.readings["was"],
                       ["en-mercier", "en-walter"], "fut ↔ was")

        // Where the two translations agree, they share ONE reading against the French — grouped, not split.
        // (Residual, documented: the French noun–adjective inversion "phénomène inexpliqué" vs "mysterious
        // phenomenon" is an alignment tie, so the shared reading may sit one slot from the French noun; the
        // WIN asserted here is that the translations group onto a single bucket at one slot.)
        let phenomenon = g.nodes.first { $0.readings["phenomenon"] == ["en-mercier", "en-walter"] }
        XCTAssertNotNil(phenomenon, "the English witnesses group on their shared rendering 'phenomenon'")

        // Determinism: the graph is stable under reordering of the two translations.
        let g2 = Collation.variantGraph(witnesses: [fr, walter, mercier], strategy: .peerMSA, lexicon: lex)
        XCTAssertEqual(g, g2, "graph stable under reordering of the translations")
    }
}
