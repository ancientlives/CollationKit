import XCTest
@testable import CollationKit

// MARK: - Peer-MSA merge (BACKLOG B14) — the acceptance suite
//
// B14 replaced the reserved `.peerMSA` fallback with a real peer merge (`PeerMSA.swift`): each witness aligns
// against the growing graph's consensus spine, not against a fixed base. These tests are the acceptance set the
// backlog item names: (1) recurring-word moves become `certain` FROM STRUCTURE where the lift said `likely`;
// (2) non-base-shared variance (the base-sensitivity gap) groups correctly; (3) output is byte-stable under
// witness reordering; (4) page-crossing move attribution survives the rewrite (the contribution most at risk);
// and (5) `.baseAnchored` output is unchanged (its goldens pin it — asserted structurally here too).

final class PeerMSATests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    // MARK: 1 — recurring-word move: `likely` under the lift, `certain` from structure under the peer merge

    /// `author` occurs twice; one occurrence moves. The pairwise post-pass pairs the displaced occurrences by
    /// elimination and — because the word recurs globally — can only call the move `likely`. The peer merge
    /// sees the whole structure: every other occurrence is matched in place, and re-pinning between identical
    /// tokens changes nothing, so the displacement is forced → `certain`. This is PAPER_NOTES §5.3 step 4
    /// (confidence from structure), and the headline acceptance criterion of B14.
    func testRecurringWordMoveIsCertainUnderPeerMSA() {
        let base = w("A", "the author wrote well and the author was famous end")
        let comp = w("B", "the wrote well author and the author was famous end")

        let lift = TokenGraph.build(witnesses: [base, comp])!
        let liftMoves = lift.edges.filter { $0.isMove }
        XCTAssertEqual(liftMoves.count, 1)
        XCTAssertEqual(liftMoves[0].confidence, .likely,
                       "the lift inherits the pairwise post-pass confidence: recurring word → likely")

        let peer = TokenGraph.buildPeerMSA(witnesses: [base, comp])!
        let peerMoves = peer.edges.filter { $0.isMove }
        XCTAssertEqual(peerMoves.count, 1)
        XCTAssertEqual(peerMoves[0].witnesses, ["B"])
        XCTAssertEqual(peerMoves[0].confidence, .certain,
                       "the peer merge derives the move from structure: the displacement is forced → certain")
    }

    // MARK: 2 — non-base-shared variance (the base-sensitivity gap)

    /// B inserts "the red rose", C inserts "a red rose"; the base has neither. The lift keys each insertion by
    /// its whole text → two unrelated nodes (B and C never see each other). The peer merge aligns C against a
    /// consensus that already CONTAINS B's insertion, so "red rose" is one reading shared by B+C and only
    /// "the|a" diverges — the base-privilege gap closed.
    func testPartiallySharedInsertionGroupsAcrossNonBaseWitnesses() {
        let ws = [w("A", "alpha beta gamma delta"),
                  w("B", "alpha beta the red rose gamma delta"),
                  w("C", "alpha beta a red rose gamma delta")]

        // The lift: two whole-run inserted nodes, no shared reading between B and C.
        let lifted = Collation.variantGraph(witnesses: ws, strategy: .baseAnchored)
        let liftedInserted = lifted.nodes.filter { $0.isInserted }
        XCTAssertEqual(liftedInserted.count, 2, "the lift cannot relate the two insertions")
        XCTAssertFalse(liftedInserted.contains { $0.readings.contains { $0.value == ["B", "C"] } })

        // The peer merge: "red rose" is ONE reading carried by B and C; the divergence is only "the|a".
        let peer = Collation.variantGraph(witnesses: ws, strategy: .peerMSA)
        let peerInserted = peer.nodes.filter { $0.isInserted }
        XCTAssertTrue(peerInserted.contains { $0.readings["red rose"]?.isSuperset(of: ["B", "C"]) == true },
                      "the shared run groups: B and C carry ONE 'red rose' reading")
        XCTAssertTrue(peerInserted.contains { $0.readings["the"] == ["B"] && $0.readings["a"] == ["C"] },
                      "only the article diverges between the two insertions")
    }

    /// Two non-base witnesses share a substitution the base lacks — both strategies must group them onto one
    /// reading (the lift already did via normalised bucketing; the peer merge must not regress it).
    func testSharedSubstitutionGroupsUnderBothStrategies() {
        let ws = [w("A", "the colour of the sky"),
                  w("B", "the hue of the sky"),
                  w("C", "the hue of the sky")]
        for strategy in [CollationStrategy.baseAnchored, .peerMSA] {
            let g = Collation.variantGraph(witnesses: ws, strategy: strategy)
            let variant = g.variantNodes.first
            XCTAssertNotNil(variant, "\(strategy.rawValue): the substitution surfaces")
            XCTAssertEqual(variant?.readings["hue"], ["B", "C"],
                           "\(strategy.rawValue): the shared reading carries both non-base witnesses")
        }
    }

    // MARK: 3 — determinism: byte-stable under witness reordering

    /// The peer merge processes non-base witnesses in sorted-id order, NOT input order, so the GRAPH is
    /// identical when the caller shuffles them (the §9 determinism bar the MSA makes harder; a progressive
    /// merge in input order would be order-sensitive). The base stays `witnesses[0]` (it is the render key),
    /// so reordering is over the non-base witnesses. (The JSON's `pairs` section is *successive input pairs*
    /// by definition, so full-output byte-equality is the wrong claim; the graph is the stable artifact.)
    func testGraphStableUnderWitnessReordering() {
        let a = w("A", "one two three four five six")
        let b = w("B", "one two altered four five six")
        let c = w("C", "one two three four changed six seven")
        let d = w("D", "zero one two three four five six")

        let orders: [[Witness]] = [[a, b, c, d], [a, d, c, b], [a, c, b, d], [a, d, b, c]]
        let graphs = orders.map { Collation.variantGraph(witnesses: $0, strategy: .peerMSA) }
        for g in graphs.dropFirst() {
            XCTAssertEqual(graphs[0], g, "peer-MSA graph must be identical under witness reordering")
        }
    }

    // MARK: 4 — the page-aware tie-break survives the rewrite (the guarded contribution)

    /// TS→PR swaps two sentences across a page break; the page-aware spine keeps the page-stable sentence and
    /// reports the page-crossing "lamps" sentence as the move. The peer merge threads per-slot pages into the
    /// same `Transposition.align`, so the attribution must survive: the move edge brackets the "lamps" nodes,
    /// not the "weary" nodes.
    func testPageCrossingMoveAttributionPreserved() {
        let ts = Samples.sixEditions[1], pr = Samples.sixEditions[2]
        let peer = TokenGraph.buildPeerMSA(witnesses: [ts, pr])!
        let moves = peer.edges.filter { $0.isMove }
        XCTAssertEqual(moves.count, 1, "the swap is a single move")

        func nodeID(containing word: String) -> Int? {
            peer.nodes.first { $0.readings.keys.contains(word) }?.id
        }
        let lamps = nodeID(containing: "lamps")!
        let weary = nodeID(containing: "weary")!
        let move = moves[0]
        XCTAssertTrue(move.from < lamps && lamps <= move.to,
                      "the move brackets the page-crossing 'lamps' sentence")
        XCTAssertFalse(move.from < weary && weary <= move.to,
                       "the page-stable 'weary' sentence is NOT the reported move")
    }

    // MARK: 5 — parity and non-breaking guarantees

    /// On in-order witness sets with plain substitutions/omissions (no moves, no insertions needing context)
    /// the two strategies agree node-for-node — peer-MSA is a generalisation, not a different apparatus.
    func testParityWithLiftOnSimpleSets() {
        let sets: [[Witness]] = [
            [w("A", "alpha beta gamma"), w("B", "alpha delta gamma")],
            [w("A", "one two three four"), w("B", "one two four"), w("C", "one two three four five")],
            Array(Samples.sixEditions[0...1]),
        ]
        for ws in sets {
            let lift = Collation.variantGraph(witnesses: ws, strategy: .baseAnchored)
            let peer = Collation.variantGraph(witnesses: ws, strategy: .peerMSA)
            XCTAssertEqual(lift, peer, "strategies agree on a simple in-order set: \(ws.map { $0.id })")
        }
    }

    /// The six-edition scenario end-to-end under peer MSA: deterministic, agreement preserved, and the
    /// substantive divergences (tired/weary/cold/bitter) all present with the right carriers.
    func testSixEditionsUnderPeerMSA() {
        let g = Collation.variantGraph(witnesses: Samples.sixEditions,
                                       normalizer: Samples.gbUSNormalizer, strategy: .peerMSA)
        let g2 = Collation.variantGraph(witnesses: Samples.sixEditions,
                                        normalizer: Samples.gbUSNormalizer, strategy: .peerMSA)
        XCTAssertEqual(g, g2, "deterministic on repeat")
        let readings = g.variantNodes.flatMap { $0.readings.keys }
        XCTAssertTrue(readings.contains("tired") && readings.contains("weary"),
                      "the tired/weary revision surfaces")
        XCTAssertTrue(readings.contains("cold") && readings.contains("bitter"),
                      "the cold/bitter revision surfaces")
    }

    /// Degenerate inputs: empty set → nil; a single witness → an all-agreement graph keyed to itself.
    func testDegenerateInputs() {
        XCTAssertNil(TokenGraph.buildPeerMSA(witnesses: []))
        let g = Collation.variantGraph(witnesses: [w("A", "just one witness")], strategy: .peerMSA)
        XCTAssertEqual(g.baseID, "A")
        XCTAssertTrue(g.variantNodes.isEmpty, "a lone witness has no points of variance")
    }
}
