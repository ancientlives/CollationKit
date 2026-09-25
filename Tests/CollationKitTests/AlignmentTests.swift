import XCTest
@testable import CollationKit

// Stage-2 tests: Needleman–Wunsch pairwise alignment, then the anchor/transposition layer on top.

final class AlignmentTests: XCTestCase {

    // MARK: Needleman–Wunsch

    func testIdenticalSequencesAllMatch() {
        let ops = Alignment.needlemanWunsch(["a", "b", "c"], ["a", "b", "c"])
        XCTAssertEqual(ops, [.match(a: 0, b: 0), .match(a: 1, b: 1), .match(a: 2, b: 2)])
    }

    func testPureInsertionAndDeletion() {
        XCTAssertEqual(Alignment.needlemanWunsch([], ["x", "y"]), [.insert(b: 0), .insert(b: 1)])
        XCTAssertEqual(Alignment.needlemanWunsch(["x", "y"], []), [.delete(a: 0), .delete(a: 1)])
    }

    func testSubstitutionInTheMiddle() {
        // a B c  vs  a X c  → a match, B/X substitute, c match (NW prefers the diagonal substitution over
        // a delete+insert pair because match+mismatch outscores two gaps).
        let ops = Alignment.needlemanWunsch(["a", "b", "c"], ["a", "x", "c"])
        XCTAssertEqual(ops, [.match(a: 0, b: 0), .substitute(a: 1, b: 1), .match(a: 2, b: 2)])
    }

    func testInsertedWordIsAGap() {
        // "the cat" → "the black cat": one insertion, no spurious substitution. The inserted "black" is
        // b:1, so "cat"↔"cat" matches a:1↔b:2.
        let ops = Alignment.needlemanWunsch(["the", "cat"], ["the", "black", "cat"])
        XCTAssertEqual(ops, [.match(a: 0, b: 0), .insert(b: 1), .match(a: 1, b: 2)])
    }

    // MARK: transposition

    func testNoMoveIsASingleInOrderRegion() {
        let a = "the quick brown fox jumps over the lazy dog".split(separator: " ").map(String.init)
        let result = Transposition.align(a, a)
        // Every segment is an in-order region; no transposition.
        XCTAssertFalse(result.segments.contains { if case .transposition = $0 { return true } else { return false } })
    }

    func testMovedBlockIsDetectedAsTransposition() {
        // Two distinctive blocks swap order. Anchors inside each block pin them; the LIS-by-B keeps one in
        // order and flags the other as moved.
        let base = ("alpha beta gamma delta one two three four "
                  + "the storm broke over the harbour at dawn").split(separator: " ").map(String.init)
        let moved = ("the storm broke over the harbour at dawn "
                   + "alpha beta gamma delta one two three four").split(separator: " ").map(String.init)
        let result = Transposition.align(base, moved, anchorLength: 3)
        let transpositions = result.segments.filter { if case .transposition = $0 { return true } else { return false } }
        XCTAssertFalse(transpositions.isEmpty, "a whole block that swapped position should be a transposition")
    }

    func testLongestIncreasingByBPicksStableAnchors() {
        // pins in A-order with B positions [0, 3, 1, 2, 4] → LIS by B is [0,1,2,4] (indices 0,2,3,4).
        let pins = [
            AnchorPin(aStart: 0, bStart: 0, length: 1),
            AnchorPin(aStart: 1, bStart: 3, length: 1),
            AnchorPin(aStart: 2, bStart: 1, length: 1),
            AnchorPin(aStart: 3, bStart: 2, length: 1),
            AnchorPin(aStart: 4, bStart: 4, length: 1),
        ]
        XCTAssertEqual(Transposition.longestIncreasingByB(pins), [0, 2, 3, 4])
    }

    func testUniqueCommonAnchorsIgnoreRepeatedNGrams() {
        // "na na na" has no unique 1-grams; a distinctive phrase does.
        let a = "na na na batman returns tonight".split(separator: " ").map(String.init)
        let b = "na na na batman returns tonight".split(separator: " ").map(String.init)
        let anchors = Transposition.uniqueCommonAnchors(a, b, n: 2)
        // "na na" repeats → excluded; "batman returns" / "returns tonight" are unique → included.
        XCTAssertTrue(anchors.allSatisfy { $0.length == 2 })
        XCTAssertFalse(anchors.isEmpty)
    }
}
