import XCTest
@testable import CollationKit

// MARK: - Token-graph merge acceptance tests (BACKLOG B11)
//
// These name the behaviour the token-graph merge delivers (docs/development/TOKEN_GRAPH_PLAN.md §5): all
// witnesses merged into one DAG where a token is a node, an out-of-spine traversal is a move edge, and an
// off-spine node is an insertion. B11 is implemented (`TokenGraph.build` / `projectedVariantGraph`), so these
// are live acceptance tests — they were the skipped scaffold that guided the build.
//
// The headline new capability is the RECURRING-WORD move: the single-word post-pass alone can only mark those
// `likely` or miss them; because the graph reads a move off structure (an out-of-spine edge), it surfaces even
// when the moved run reuses common words.

final class TokenGraphTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    private func requireGraph(_ witnesses: [Witness]) throws -> TokenGraph {
        try XCTUnwrap(TokenGraph.build(witnesses: witnesses), "TokenGraph.build should build for a non-empty set")
    }

    /// Single-word move — parity with today's post-pass, but via the graph: `author` moves (one transposition),
    /// `is` is inserted.
    func testSingleWordMoveIsOneTransposition() throws {
        let g = try requireGraph([w("A", "the well known author"), w("B", "the author is well known")])
        XCTAssertTrue(g.edges.contains { $0.isMove }, "the displaced word should be a move edge")
    }

    /// Recurring-word move — the capability the post-pass lacks: a moved run whose words recur elsewhere is
    /// still reported as a move (certain), not delete+insert or a `likely` guess.
    func testRecurringWordMoveIsRecovered() throws {
        // "spring" recurs; the moved clause reuses common words — the post-pass would struggle, the graph should not.
        let g = try requireGraph([
            w("A", "in spring the river rose and in spring the fields were green"),
            w("B", "in spring the fields were green and in spring the river rose"),
        ])
        XCTAssertTrue(g.edges.contains { $0.isMove }, "a recurring-word move must still be a move")
    }

    /// N-witness merge — agreement nodes shared by all; variance branches where they differ.
    func testNWitnessAgreementAndVariance() throws {
        let g = try requireGraph([w("A", "the cat sat"), w("B", "the cat sat"), w("C", "the dog sat")])
        XCTAssertTrue(g.nodes.contains { $0.isAgreement }, "‘the’/‘sat’ are agreement nodes")
        XCTAssertTrue(g.nodes.contains { !$0.isAgreement }, "cat/dog is a variance node")
    }

    /// Pure insertion — an off-spine node carrying the inserter's reading, WITHOUT B6c's insertionAnchor
    /// scaffolding (the graph places it structurally).
    func testPureInsertionIsOffSpineNode() throws {
        let g = try requireGraph([w("A", "alpha beta"), w("B", "alpha inserted beta")])
        // The inserted token is a node not on every witness's path; the projection must surface it.
        XCTAssertTrue(g.nodes.contains { node in
            node.readings.values.contains { $0.surface == "inserted" }
        }, "the inserted token should be a graph node")
    }

    /// Determinism — identical graph on repeat (guards the sorted/stable output rule, ALGORITHMS §9).
    func testGraphIsDeterministic() throws {
        let ws = [w("A", "a b c"), w("B", "a x b c"), w("C", "a b c")]
        let g1 = try requireGraph(ws)
        let g2 = try requireGraph(ws)
        XCTAssertEqual(g1, g2)
    }

    /// Projection — the token-graph projects onto the existing `VariantGraph` shape so renderers are unchanged.
    func testProjectsToVariantGraph() throws {
        let g = try requireGraph([w("A", "the cat sat"), w("B", "the dog sat")])
        let projected = try XCTUnwrap(g.projectedVariantGraph(baseID: "A"), "projection should be produced")
        XCTAssertFalse(projected.nodes.isEmpty, "projection yields apparatus-facing nodes")
        // cat/dog is the one point of variance; the/sat agree.
        XCTAssertEqual(projected.variantNodes.count, 1, "one variant node (cat/dog)")
    }

    /// The token-graph is the substrate `Collation.variantGraph` now projects through: the public N-witness
    /// apparatus and the graph's own projection agree (guards the migration wiring, plan §4 step 3).
    func testEngineVariantGraphMatchesProjection() throws {
        let ws = [w("A", "the cat sat"), w("B", "the cat sat"), w("C", "the dog sat")]
        let viaEngine = Collation.variantGraph(witnesses: ws)
        let viaGraph = try XCTUnwrap(TokenGraph.build(witnesses: ws)?.projectedVariantGraph(baseID: "A"))
        XCTAssertEqual(viaEngine, viaGraph, "the engine routes variantGraph through the token-graph projection")
    }
}
