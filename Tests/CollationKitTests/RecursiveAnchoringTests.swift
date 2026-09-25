import XCTest
@testable import CollationKit

// Recursive anchoring (DEVELOPMENT_LOG 2026-06-27): a passage that BOTH moves AND is edited inside must be
// reported as ONE transposition carrying its internal edits — not as a tail-only move plus delete+insert
// churn for the changed head. The move is bridged across a bounded internal mismatch, then collated against
// itself so the edit surfaces as a `withinTransposition` variation.

final class RecursiveAnchoringTests: XCTestCase {

    private func w(_ id: String, _ t: String) -> Witness { Witness(id: id, text: t) }

    func testMovedSentenceWithOneInternalWordChange() {
        // "they were tired and the road had been very long indeed" moves AFTER the lamps sentence, and
        // "tired" → "weary" inside it.
        let a = w("A", "they were tired and the road had been very long indeed.\n"
                     + "the lamps were lit along the quay tonight friend.")
        let b = w("B", "the lamps were lit along the quay tonight friend.\n"
                     + "they were weary and the road had been very long indeed.")
        let r = Collation.collate(base: a, compared: b)

        XCTAssertEqual(r.transpositions, 1, "the whole sentence is one move")
        XCTAssertEqual(r.insertions, 0, "no insert churn for the changed head")
        XCTAssertEqual(r.deletions, 0, "no delete churn for the changed head")
        XCTAssertEqual(r.substitutions, 1, "the internal edit is one substitution")

        // The transposition spans the WHOLE sentence, head included.
        let move = r.variations.first { $0.type == .transposition }!
        XCTAssertTrue(move.baseReading.contains("they were tired"), "the move includes the edited head")
        XCTAssertTrue(move.baseReading.contains("very long indeed"), "…and the tail")

        // The internal edit is reported, flagged as within the move.
        let edit = r.variations.first { $0.type == .substitution }!
        XCTAssertTrue(edit.withinTransposition, "the edit is inside the transposed passage")
        XCTAssertEqual(edit.baseReading, "tired")
        XCTAssertEqual(edit.comparedReading, "weary")
    }

    func testMovedSentenceWithTwoInternalChanges() {
        // Two edits inside the moved block (tired→weary AND long→short).
        let a = w("A", "they were tired and the road had been very long indeed.\n"
                     + "the lamps were lit along the quay tonight friend.")
        let b = w("B", "the lamps were lit along the quay tonight friend.\n"
                     + "they were weary and the road had been very short indeed.")
        let r = Collation.collate(base: a, compared: b)
        XCTAssertEqual(r.transpositions, 1)
        XCTAssertEqual(r.insertions + r.deletions, 0, "no churn around the move")
        let edits = r.variations.filter { $0.type == .substitution }
        XCTAssertEqual(edits.count, 2, "both internal edits recovered")
        XCTAssertTrue(edits.allSatisfy { $0.withinTransposition })
        XCTAssertEqual(Set(edits.map { $0.comparedReading }), ["weary", "short"])
    }

    func testPureMoveStillHasNoInternalEdits() {
        // A clean move (no internal change) must NOT spuriously emit within-transposition edits.
        let a = w("A", "first distinctive clause here.\nsecond separate clause now.")
        let b = w("B", "second separate clause now.\nfirst distinctive clause here.")
        let r = Collation.collate(base: a, compared: b)
        XCTAssertEqual(r.transpositions, 1)
        XCTAssertFalse(r.variations.contains { $0.withinTransposition },
                       "a pure move has no internal edits")
        XCTAssertEqual(r.substitutions + r.insertions + r.deletions, 0)
    }

    func testUnrelatedTextIsNotSwallowedByBridging() {
        // The bounded bridge must not absorb arbitrary distant text. A move with a LARGE unrelated change
        // beside it should not pull that change into the transposition as if it were internal.
        let a = w("A", "keep this opening exactly as written here always.\n"
                     + "the travelling caravan crossed the wide desert slowly.")
        let b = w("B", "the travelling caravan crossed the wide desert slowly.\n"
                     + "keep this opening exactly as written here always.")
        let r = Collation.collate(base: a, compared: b)
        // A clean swap of two intact sentences → one transposition, no internal edits, no churn.
        XCTAssertEqual(r.transpositions, 1)
        XCTAssertEqual(r.substitutions + r.insertions + r.deletions, 0)
    }

    // The resync helpers, tested directly on token-key arrays.
    func testResyncBridgesABoundedMismatch() {
        // before the block, a[2]="x" vs b[2]="y" mismatch, but a[1]==b[1]=="shared" one step back.
        let a = ["pre", "shared", "x"]
        let b = ["pre", "shared", "y"]
        let onSpine = [Bool](repeating: false, count: 3)
        let resync = Transposition.resync(a, b, beforeA: 2, beforeB: 2, gap: 4,
                                          onSpine: onSpine, onSpineB: onSpine)
        XCTAssertEqual(resync?.0, 1, "resyncs back to the shared token at index 1")
        XCTAssertEqual(resync?.1, 1)
    }

    func testResyncReturnsNilBeyondGap() {
        let a = ["m0", "m1", "m2", "m3", "m4", "shared"]
        let b = ["n0", "n1", "n2", "n3", "n4", "shared"]
        let onSpine = [Bool](repeating: false, count: 6)
        // The only match ("shared") is 5 back — beyond a gap of 2.
        XCTAssertNil(Transposition.resync(a, b, beforeA: 4, beforeB: 4, gap: 2,
                                          onSpine: onSpine, onSpineB: onSpine))
    }
}
