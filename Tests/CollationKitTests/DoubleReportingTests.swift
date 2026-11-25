import XCTest
@testable import CollationKit

// MARK: - Nothing is reported twice (release 1 review, blocker B8)
//
// Three routes reported the same text twice: (1) the displaced-word recovery rebuilt a carved deletion as one
// `min…max` range, so a word moved out of its MIDDLE stayed inside it; (2) a region's edits on both sides of an
// anchor-path move merged into one variation whose range spanned the moved words; (3) under `.diplomatic`, where
// punctuation is aligned, the punctuation overlay reported every punctuation change a second time.

final class DoubleReportingTests: XCTestCase {

    private func collate(_ a: String, _ b: String, normalizer: Normalizer = .substantive,
                         recordPunctuation: Bool = false) -> CollationResult {
        Collation.collate(base: Witness(id: "A", text: a), compared: Witness(id: "B", text: b),
                          normalizer: normalizer, recordPunctuation: recordPunctuation)
    }

    func testAWordMovedOutOfTheMiddleOfADeletionIsNotAlsoDeleted() {
        let r = collate("one two three alpha zebra beta four five six seven eight nine",
                        "one two three four five six zebra seven eight nine")
        XCTAssertEqual(r.variations.filter { $0.type == .deletion }.map(\.baseReading), ["alpha", "beta"])
        XCTAssertEqual(r.variations.filter { $0.type == .transposition }.map(\.baseReading), ["zebra"])
    }

    func testDiplomaticPunctuationIsReportedOnce() {
        let diplomatic = collate("Hello, world and friends", "Hello; world and friends",
                                 normalizer: .diplomatic, recordPunctuation: true)
        XCTAssertEqual(diplomatic.variations.count, 1)
        XCTAssertEqual(diplomatic.variations.first?.type, .substitution)
        let overlay = collate("Hello, world and friends", "Hello; world and friends", recordPunctuation: true)
        XCTAssertEqual(overlay.variations.count, 1)
        XCTAssertEqual(overlay.variations.first?.type, .variantSpelling)
    }

    func testAMovedPassageNeverOverlapsAnotherVariant() {
        // Seeded fuzz: distinctive tokens so anchors exist, with blocks moved and words changed around them.
        var rng = SplitMix64(seed: 0xB8)
        var checked = 0
        for round in 0..<300 {
            let n = 30 + Int(rng.next() % 40)
            let base = (0..<n).map { "w\($0)r\(round)" }
            var compared = base
            // Move one block of 3–6 tokens.
            let len = 3 + Int(rng.next() % 4)
            let from = Int(rng.next() % UInt64(n - len))
            let block = Array(compared[from..<(from + len)])
            compared.removeSubrange(from..<(from + len))
            compared.insert(contentsOf: block, at: Int(rng.next() % UInt64(compared.count + 1)))
            // Change, delete and insert a few words anywhere (including inside or around the moved block).
            for _ in 0..<(2 + Int(rng.next() % 4)) {
                let i = Int(rng.next() % UInt64(compared.count))
                switch rng.next() % 3 {
                case 0: compared[i] = "x\(rng.next() % 1000)"
                case 1: compared.remove(at: i)
                default: compared.insert("y\(rng.next() % 1000)", at: i)
                }
            }
            let r = collate(base.joined(separator: " "), compared.joined(separator: " "))
            let moves = r.variations.filter { $0.type == .transposition }
            let others = r.variations.filter { $0.type != .transposition && !$0.withinTransposition }
            for m in moves {
                for v in others {
                    if let a = m.baseTokenRange, let b = v.baseTokenRange {
                        XCTAssertFalse(a.overlaps(b), "round \(round): '\(m.baseReading)' also inside '\(v.baseReading)'")
                    }
                    if let a = m.comparedTokenRange, let b = v.comparedTokenRange {
                        XCTAssertFalse(a.overlaps(b), "round \(round): '\(m.comparedReading)' also inside '\(v.comparedReading)'")
                    }
                }
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 100, "the fuzz exercised enough moves to be meaningful")
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
