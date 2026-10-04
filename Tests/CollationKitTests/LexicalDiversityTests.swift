import XCTest
@testable import CollationKit

// Lexical-diversity cost mitigation (DEVELOPMENT_LOG 2026-06-27): the anchor pass chunks the O(n·m) matrix
// only when unique shared n-grams exist, so low-diversity text used to degrade to one huge NW. Two
// mitigations are tested here: ADAPTIVE anchoring (retry shorter n-grams when 3-grams are too sparse) and a
// BOUNDED no-anchor fallback (positional chunking) that keeps adversarial input responsive.

final class LexicalDiversityTests: XCTestCase {

    func testAdaptiveAnchoringFindsShorterAnchorsWhenTrigramsAreSparse() {
        // Build sequences where unique TRIgrams are rare but unique BIgrams exist. Repeated function words
        // around a few distinctive bigrams.
        let a = "the the the alpha beta the the the gamma delta the the the".split(separator: " ").map(String.init)
        let b = "the the the alpha beta the the the gamma delta the the the".split(separator: " ").map(String.init)
        let tri = Transposition.uniqueCommonAnchors(a, b, n: 3)
        let adaptive = Transposition.adaptiveAnchors(a, b, startN: 3)
        XCTAssertGreaterThanOrEqual(adaptive.count, tri.count,
                                    "adaptive anchoring finds at least as many landmarks as fixed trigrams")
        XCTAssertFalse(adaptive.isEmpty, "shorter n-grams recover landmarks fixed trigrams miss")
    }

    func testAdaptivePrefersLongerAnchorsWhenTheySuffice() {
        // Distinctive prose: trigrams are plentiful, so adaptive should keep n=3 (longer = more reliable).
        let a = "the quick brown fox jumps over the lazy sleeping dog tonight".split(separator: " ").map(String.init)
        let anchors = Transposition.adaptiveAnchors(a, a, startN: 3)
        XCTAssertTrue(anchors.allSatisfy { $0.length == 3 }, "keeps trigrams when they already anchor well")
    }

    func testPathologicalLowDiversityLongInputStaysFast() {
        // The worst case the characterization names: a long, highly repetitive text (tiny lexicon) where
        // almost no n-gram is unique, collated against a lightly edited copy. The bounded (banded) fallback
        // must keep this responsive instead of running a multi-thousand-square full matrix.
        let lexicon = ["the", "and", "a", "of", "to", "in"]
        var words: [String] = []
        for i in 0..<4000 { words.append(lexicon[i % lexicon.count]) }
        let baseText = words.joined(separator: " ")
        var comp = words
        comp[2000] = "INSERTED"                       // one tiny edit deep in the middle
        let start = Date()
        let r = Collation.collate(base: Witness(id: "a", text: baseText),
                                  compared: Witness(id: "b", text: comp.joined(separator: " ")))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "banded fallback keeps adversarial low-diversity input responsive; took \(elapsed)s")
        XCTAssertFalse(r.variations.isEmpty, "the edit is still detected")
    }

    func testBoundedNWMatchesFullNWBelowTheCap() {
        // Below the cell cap, boundedNW must be EXACTLY full NW (banding only engages above it).
        let a = "alpha beta gamma delta".split(separator: " ").map(String.init)
        let b = "alpha BETA gamma delta".split(separator: " ").map(String.init)
        XCTAssertEqual(Transposition.boundedNW(a, b, scores: AlignmentScores()),
                       Alignment.needlemanWunsch(a, b, scores: AlignmentScores()))
    }

    func testBandedNWEqualsFullNWWhenWithinTheBand() {
        // The real win over positional chunking: when the true alignment stays within the band, banded NW is
        // GLOBALLY OPTIMAL — identical to full NW — including across what would have been chunk seams.
        let a = (0..<600).map { "w\($0)" }             // distinctive, co-linear
        var b = a
        b.insert("EXTRA", at: 50)                       // a single early insert → everything after drifts by 1
        b[400] = "CHANGED"                              // an edit well past any chunk boundary
        let (banded, hitEdge) = Alignment.banded(a, b, band: 16)
        XCTAssertFalse(hitEdge, "drift of 1 stays well inside a band of 16")
        XCTAssertEqual(banded, Alignment.needlemanWunsch(a, b), "banded == full NW within the band")
    }

    func testBandedNWReturnsCompleteAlignmentOnAdversarialInput() {
        // On structureless input the band is capped (approximate), but the op stream must still be COMPLETE —
        // every A token represented exactly once.
        let a = (0..<2500).map { _ in "x" }
        var b = a; b[1500] = "y"
        let ops = Transposition.boundedNW(a, b, scores: AlignmentScores())
        let aCovered = ops.compactMap { op -> Int? in
            switch op { case .match(let i, _), .substitute(let i, _), .delete(let i): return i; default: return nil }
        }
        XCTAssertEqual(Set(aCovered).count, a.count, "every A token appears exactly once in the alignment")
    }

    func testBandWidensWhenPathHitsEdge() {
        // A drift larger than the initial band should be recovered by auto-widening (converges to full NW).
        let a = (0..<400).map { "t\($0)" }
        var b = a
        for _ in 0..<30 { b.insert("pad", at: 10) }    // 30-token drift, beyond a band of 8
        let widened = Alignment.bandedAutoWidening(a, b, initialBand: 8, maxBand: 256)
        XCTAssertEqual(widened, Alignment.needlemanWunsch(a, b),
                       "auto-widening recovers the optimal alignment once the band covers the drift")
    }
}
