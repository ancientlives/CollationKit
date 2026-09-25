import XCTest
@testable import CollationKit

// The headline scenario: collating the witness-set a literary work actually accrues —
//   1. manuscript  2. typescript  3. proofs  4. 1st edition (GB)  5. 1st edition (US)  6. Uniform edition
// — including the cases that defeat a line `diff`: a passage MOVED across a page boundary, GB/US spelling
// (accidental, not substantive), and an N-witness apparatus.
//
// Each witness uses an explicit page break (`<!-- page break -->`) so "across pages" is real, not implied.

final class LiteraryEditionsTests: XCTestCase {

    // A short two-page opening that evolves across the six editions.
    //
    // Page 1 = an opening paragraph; Page 2 = a closing paragraph. In the proofs the author MOVED the
    // "lamps were lit" sentence from page 2 up to page 1 — a transposition ACROSS a page boundary.

    private let manuscript = Witness(id: "MS", text: """
    The travellers reached the grey harbour at dusk.
    They were tired and the road had been long.

    <!-- page break -->

    The lamps were lit along the quay one by one.
    A cold wind came in from the open sea.
    """)

    private let typescript = Witness(id: "TS", text: """
    The travellers reached the grey harbour at dusk.
    They were weary and the road had been long.

    <!-- page break -->

    The lamps were lit along the quay one by one.
    A cold wind came in from the open sea.
    """)

    // Proofs: the "lamps were lit" sentence is MOVED up to page 1 (a cross-page transposition).
    private let proofs = Witness(id: "PR", text: """
    The travellers reached the grey harbour at dusk.
    The lamps were lit along the quay one by one.
    They were weary and the road had been long.

    <!-- page break -->

    A cold wind came in from the open sea.
    """)

    // GB 1st edition: British spelling ("grey", "harbour", "travellers").
    private let gbEdition = Witness(id: "GB1", text: """
    The travellers reached the grey harbour at dusk.
    The lamps were lit along the quay one by one.
    They were weary and the road had been long.

    <!-- page break -->

    A cold wind came in from the open sea.
    """)

    // US 1st edition: American spelling ("gray", "harbor", "travelers") — an ACCIDENTAL, not a substantive
    // change, when GB/US folding is on.
    private let usEdition = Witness(id: "US1", text: """
    The travelers reached the gray harbor at dusk.
    The lamps were lit along the quay one by one.
    They were weary and the road had been long.

    <!-- page break -->

    A cold wind came in from the open sea.
    """)

    // Uniform edition: a genuine substantive revision ("cold wind" → "bitter wind").
    private let uniform = Witness(id: "UNI", text: """
    The travelers reached the gray harbor at dusk.
    The lamps were lit along the quay one by one.
    They were weary and the road had been long.

    <!-- page break -->

    A bitter wind came in from the open sea.
    """)

    private var gbUS: Normalizer { Normalizer(spellingEquivalents: Normalizer.gbUSSpelling) }

    // MARK: pairwise variants between successive editions

    func testManuscriptToTypescriptIsASingleWordSubstitution() {
        let r = Collation.collate(base: manuscript, compared: typescript)
        XCTAssertEqual(r.substitutions, 1, "only 'tired' → 'weary' changed")
        let sub = r.variations.first { $0.type == .substitution }
        XCTAssertEqual(sub?.baseReading, "tired")
        XCTAssertEqual(sub?.comparedReading, "weary")
    }

    func testProofsMovedSentenceIsTranspositionNotDeleteInsertChurn() {
        // TS → PR reorders two sentences either side of the page break: "the lamps were lit…" and "they were
        // weary…" swap relative order. The engine must report ONE transposition for the swap — NOT a large
        // deletion (where a sentence was) plus an insertion (where it went), the diff failure mode.
        let r = Collation.collate(base: typescript, compared: proofs)
        XCTAssertEqual(r.transpositions, 1, "the reorder is a single transposition")
        XCTAssertEqual(r.insertions, 0)
        XCTAssertEqual(r.deletions, 0)
        XCTAssertEqual(r.substitutions, 0)

        // The transposition's base and compared readings are the SAME text (a move, not a rewrite).
        let move = r.variations.first { $0.type == .transposition }
        XCTAssertNotNil(move)
        XCTAssertEqual(move!.baseReading, move!.comparedReading,
                       "a transposition carries identical readings on both sides")

        // Whichever of the two swapped sentences the engine anchors on, the OTHER must not surface as
        // delete+insert churn — the whole reorder is one transposition.
        XCTAssertTrue(r.variations.allSatisfy { $0.type == .transposition },
                      "the reorder produces only the transposition, no insert/delete churn")
    }

    func testCrossPageMoveIsAttributedToTheSentenceThatChangedPage() {
        // The page-aware tie-break (DEVELOPMENT_LOG 2026-06-27) resolves the symmetry of a two-sentence swap
        // in favour of the block that actually changed page: "the lamps were lit…" moved from page 1 (after
        // the break in TS) to page 0 (before it in PR), so THAT sentence is the reported transposition and it
        // is flagged crossesPage — not the page-stable "they were weary…" sentence.
        let r = Collation.collate(base: typescript, compared: proofs)
        XCTAssertEqual(r.transpositions, 1)
        let move = r.variations.first { $0.type == .transposition }!
        XCTAssertTrue(move.baseReading.lowercased().contains("lamps"),
                      "the moved block is the page-crossing 'lamps were lit' sentence, got: \(move.baseReading)")
        XCTAssertTrue(move.crossesPage, "and it is flagged as crossing a page")
        XCTAssertEqual(move.basePage, 1)
        XCTAssertEqual(move.comparedPage, 0)
        // Navigable fields populated on both sides for the viewer.
        XCTAssertNotNil(move.baseTokenRange)
        XCTAssertNotNil(move.comparedTokenRange)
        XCTAssertFalse(r.crossPageVariations.isEmpty)
    }

    func testGBvsUSFirstEditionsHaveNoSubstantiveVariants() {
        let r = Collation.collate(base: gbEdition, compared: usEdition, normalizer: gbUS)
        XCTAssertTrue(r.variations.isEmpty,
                      "GB and US 1st editions differ only in accidental spelling; none should be substantive")
    }

    func testGBvsUSWithoutFoldingExposesSpellingAsVariants() {
        let r = Collation.collate(base: gbEdition, compared: usEdition, normalizer: .substantive)
        XCTAssertGreaterThanOrEqual(r.substitutions, 1,
                                    "without GB/US folding the spelling differences appear as variants")
    }

    func testUniformEditionRevisesTheWindSubstantively() {
        let r = Collation.collate(base: usEdition, compared: uniform, normalizer: gbUS)
        XCTAssertEqual(r.substitutions, 1, "only 'cold' → 'bitter' changed")
        XCTAssertEqual(r.variations.first { $0.type == .substitution }?.comparedReading, "bitter")
    }

    // MARK: N-witness apparatus across all six editions

    func testVariantGraphAcrossAllSixEditions() {
        let witnesses = [manuscript, typescript, proofs, gbEdition, usEdition, uniform]
        let graph = Collation.variantGraph(witnesses: witnesses, normalizer: gbUS)
        XCTAssertEqual(graph.baseID, "MS")

        // There IS variation across the set (tired/weary, cold/bitter, the move) → variant nodes exist.
        XCTAssertFalse(graph.variantNodes.isEmpty, "the six editions disagree in several places")

        // The opening words ("the travellers reached") are shared by every witness → an agreement node
        // where all six ids are present under a single reading.
        let agreementNodes = graph.nodes.filter { !$0.isVariant }
        XCTAssertTrue(agreementNodes.contains { node in
            node.readings.values.contains { $0.count == witnesses.count }
        }, "stable opening text is carried by all six witnesses as one reading")
    }

    func testFullSetIsDeterministic() {
        let witnesses = [manuscript, typescript, proofs, gbEdition, usEdition, uniform]
        let g1 = Collation.variantGraph(witnesses: witnesses, normalizer: gbUS)
        let g2 = Collation.variantGraph(witnesses: witnesses, normalizer: gbUS)
        XCTAssertEqual(g1, g2, "collation is deterministic — same witnesses, same apparatus")
    }
}
