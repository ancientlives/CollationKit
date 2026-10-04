import XCTest
@testable import CollationKit

// MARK: - Anchor overlap (release 1 review, blocker B1)
//
// Anchors are de-overlapped in A only, so two anchors can share B tokens. Before the fix, two spine anchors that
// overlapped in B emitted the shared B tokens as matches twice, and a moved block could claim B tokens the spine
// already owned. Either way the base tokens on the other side of the duplicate match were never reported: real
// differences vanished from the apparatus with no warning. These tests pin the invariant that every token in
// either witness is used at most once by an alignment, and the two minimal reproductions from the review.

final class AnchorOverlapTests: XCTestCase {

    private func collate(_ a: String, _ b: String) -> CollationResult {
        Collation.collate(base: Witness(id: "A", text: a), compared: Witness(id: "B", text: b))
    }

    /// Every A index and every B index used by the alignment, with multiplicity: matches and substitutions use
    /// both sides, deletions A, insertions B, and a transposition claims its whole span on each side.
    private func usage(_ alignment: SegmentAlignment) -> (a: [Int: Int], b: [Int: Int]) {
        var a: [Int: Int] = [:], b: [Int: Int] = [:]
        for segment in alignment.segments {
            switch segment {
            case .region(let ops):
                for op in ops {
                    switch op {
                    case .match(let i, let j), .substitute(let i, let j): a[i, default: 0] += 1; b[j, default: 0] += 1
                    case .delete(let i): a[i, default: 0] += 1
                    case .insert(let j): b[j, default: 0] += 1
                    }
                }
            case .transposition(let aRange, let bRange, _):
                for i in aRange { a[i, default: 0] += 1 }
                for j in bRange { b[j, default: 0] += 1 }
            }
        }
        return (a, b)
    }

    private func assertEachTokenUsedOnce(_ a: [String], _ b: [String], file: StaticString = #filePath, line: UInt = #line) {
        let (ua, ub) = usage(Transposition.align(a, b))
        XCTAssertEqual(Set(ua.keys), Set(0..<a.count), "every base token is accounted for", file: file, line: line)
        XCTAssertEqual(Set(ub.keys), Set(0..<b.count), "every compared token is accounted for", file: file, line: line)
        XCTAssertTrue(ua.values.allSatisfy { $0 == 1 }, "no base token is used twice: \(ua.filter { $0.value > 1 })",
                      file: file, line: line)
        XCTAssertTrue(ub.values.allSatisfy { $0 == 1 }, "no compared token is used twice: \(ub.filter { $0.value > 1 })",
                      file: file, line: line)
    }

    func testOverlappingSpineAnchorsDoNotHideADeletion() {
        // "alpha beta gamma" and "beta gamma zeta" are both unique-in-both 3-grams; in B they overlap on "beta gamma".
        // Before the fix only "delta epsilon" was reported and the second "beta gamma" silently matched B again.
        let a = "alpha beta gamma delta epsilon beta gamma zeta"
        let b = "alpha beta gamma zeta"
        assertEachTokenUsedOnce(a.split(separator: " ").map(String.init), b.split(separator: " ").map(String.init))
        let deletions = collate(a, b).variations.filter { $0.type == .deletion }
        XCTAssertEqual(deletions.map(\.baseReading), ["delta epsilon beta gamma"])
    }

    func testMovedBlockDoesNotClaimSpineTokens() {
        // The moved w-block's anchor "z w1 w2" overlaps the spine anchor "x y z" on B's "z". Before the fix the move
        // claimed that "z", so A's second "z" was never reported.
        let s = (1...30).map { "s\($0)" }.joined(separator: " ")
        let w = (1...20).map { "w\($0)" }.joined(separator: " ")
        let a = "x y z \(s) z \(w) end1 end2 end3"
        let b = "x y z \(w) \(s) end1 end2 end3"
        assertEachTokenUsedOnce(a.split(separator: " ").map(String.init), b.split(separator: " ").map(String.init))
        let result = collate(a, b)
        let moves = result.variations.filter { $0.type == .transposition }
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.comparedReading, w, "the move is exactly the w-block")
        XCTAssertTrue(result.variations.contains { $0.type == .deletion && $0.baseReading == "z" },
                      "the base's second 'z' is reported as deleted")
    }

    func testNoTokenIsEverUsedTwice() {
        // Seeded fuzz over a small vocabulary: repetitive enough that unique n-grams overlap in B and blocks move.
        var rng = SplitMix64(seed: 0xB1)
        let vocab = ["a", "b", "c", "d", "e", "f", "g", "h"]
        for _ in 0..<400 {
            let base = (0..<(12 + Int(rng.next() % 40))).map { _ in vocab[Int(rng.next() % UInt64(vocab.count))] }
            var compared = base
            // Shuffle a few spans and drop or insert a few tokens.
            for _ in 0..<Int(rng.next() % 4) where compared.count > 6 {
                let i = Int(rng.next() % UInt64(compared.count - 3))
                let span = Array(compared[i..<(i + 3)])
                compared.removeSubrange(i..<(i + 3))
                compared.insert(contentsOf: span, at: Int(rng.next() % UInt64(compared.count + 1)))
            }
            if rng.next() % 2 == 0, !compared.isEmpty { compared.remove(at: Int(rng.next() % UInt64(compared.count))) }
            if rng.next() % 2 == 0 { compared.insert(vocab[Int(rng.next() % 8)], at: Int(rng.next() % UInt64(compared.count + 1))) }
            assertEachTokenUsedOnce(base, compared)
        }
    }
}

/// A tiny deterministic PRNG (SplitMix64), so the fuzz above is reproducible on every platform.
private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
