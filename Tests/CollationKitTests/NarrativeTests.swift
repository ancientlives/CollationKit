import XCTest
@testable import CollationKit

// MARK: - CollationNarrative — the plain-prose "story" of a collation
//
// The narrative turns a pairwise `CollationResult` (+ the two witness texts) into a short prose account of how,
// where, and how much the compared witness differs from the base, ending with an alignment-quality verdict. These
// tests pin the contract: it is deterministic, states the extent + dominant kind, distinguishes identical texts,
// and reports the alignment as sound/worth-checking from the co-linearity of the correspondence points.

final class NarrativeTests: XCTestCase {

    private func collate(_ a: String, _ b: String) -> (CollationResult, String, String) {
        (Collation.collate(base: Witness(id: "A", text: a), compared: Witness(id: "B", text: b)), a, b)
    }

    func testIdenticalTextsSayNoVariants() {
        let (r, a, b) = collate("the quick brown fox", "the quick brown fox")
        let s = CollationNarrative.summary(r, base: a, compared: b)
        XCTAssertTrue(s.contains("identical"), "identical texts are described as such")
        XCTAssertFalse(s.contains("differs from"), "no change language when there are no variants")
    }

    func testReportsExtentAndDominantKind() {
        // A clear substitution-dominated change: three words swapped in a longer sentence.
        let base = "the sailor watched the grey harbour at dawn before the long voyage south"
        let comp = "the sailor watched the dark harbour at dusk before the short voyage south"
        let r = Collation.collate(base: Witness(id: "A", text: base), compared: Witness(id: "B", text: comp))
        let s = CollationNarrative.summary(r, base: base, compared: comp)
        XCTAssertTrue(s.contains("differs from"), "states that B differs from A")
        XCTAssertTrue(s.contains("substitution"), "names the (dominant) substitution kind")
        XCTAssertTrue(s.contains("substantive collation"), "explains why no accidentals are listed")
        XCTAssertFalse(s.contains("were checked"), "never claims accidentals were checked (release 1 review)")
    }

    func testSingleLikelyMoveIsNotDescribedAsOneOfMany() {
        // A short phrase displaced near the diagonal of a LONG pair is the engine's one `.likely` move (the
        // construction from MoveRecoveryTests). The prose used to read "1 of these are reported as possible moves
        // …, the rest as certain" when there was no rest.
        let phrase = ["off", "the", "rocks"]
        let backbone = (0..<6000).map { "s\($0)" }
        let base = (Array(backbone[..<3001]) + phrase + Array(backbone[3001...])).joined(separator: " ")
        let comp = (Array(backbone[..<3011]) + phrase + Array(backbone[3011...])).joined(separator: " ")
        let r = Collation.collate(base: Witness(id: "A", text: base), compared: Witness(id: "B", text: comp))
        XCTAssertEqual(r.variations.filter { $0.type == .transposition && $0.confidence == .likely }.count, 1)
        let s = CollationNarrative.summary(r, base: base, compared: comp)
        XCTAssertTrue(s.contains("1 passage was relocated; it is reported as a *possible* move"), s)
        XCTAssertFalse(s.contains("of these are"), "no number disagreement")
        XCTAssertFalse(s.contains("the rest as certain"), "no orphaned clause when every move is likely")
    }

    func testAlignmentVerdictSoundForColinearChanges() {
        // Changes spread co-linearly (each witness word replaced in place) → a sound alignment verdict.
        let base = (1...60).map { "word\($0)" }.joined(separator: " ")
        let comp = (1...60).map { $0 % 5 == 0 ? "changed\($0)" : "word\($0)" }.joined(separator: " ")
        let r = Collation.collate(base: Witness(id: "A", text: base), compared: Witness(id: "B", text: comp))
        let s = CollationNarrative.summary(r, base: base, compared: comp)
        XCTAssertTrue(s.contains("alignment is sound"), "co-linear in-place changes ⇒ sound alignment. Got: \(s)")
    }

    func testDeterministic() {
        let (r, a, b) = collate("alpha bravo charlie delta echo foxtrot",
                                "alpha bravo CHARLIE delta ECHO foxtrot")
        XCTAssertEqual(CollationNarrative.summary(r, base: a, compared: b),
                       CollationNarrative.summary(r, base: a, compared: b), "pure/deterministic")
    }

    func testLabelsOverrideIds() {
        let (r, a, b) = collate("one two three", "one four three")
        let s = CollationNarrative.summary(r, base: a, compared: b, labels: (base: "MS", compared: "PR"))
        XCTAssertTrue(s.contains("PR differs from MS"), "custom witness labels are used in the prose")
    }
}
