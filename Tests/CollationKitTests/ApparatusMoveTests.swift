import XCTest
@testable import CollationKit

// MARK: - Moves in the critical apparatus (release 1 review, blocker B3)
//
// A moved passage agrees with the base word for word, so it never becomes a variant node; the apparatus, which was
// built only from variant nodes, therefore omitted every transposition. A move-only collation printed "(no points of
// variance)". The variant graph now carries its moves (`VariantGraph.moves`, read off the token graph's move
// edges) and the apparatus emits one transposition entry per moved passage.

final class ApparatusMoveTests: XCTestCase {

    private func witnesses(_ texts: [(String, String)]) -> [Witness] { texts.map { Witness(id: $0.0, text: $0.1) } }

    func testAMoveOnlyCollationHasAnApparatusEntry() {
        for strategy in [CollationStrategy.baseAnchored, .peerMSA] {
            let graph = Collation.variantGraph(
                witnesses: witnesses([("A", "she opened the door and turned to leave at last"),
                                      ("B", "at last she opened the door and turned to leave")]),
                strategy: strategy)
            let entries = Apparatus.entries(from: graph)
            XCTAssertEqual(entries.count, 1, "\(strategy)")
            XCTAssertEqual(entries.first?.type, .transposition, "\(strategy)")
            XCTAssertEqual(entries.first?.lemma, "at last", "\(strategy)")
            XCTAssertEqual(entries.first?.variants.first?.sigla, ["B"], "\(strategy)")
            XCTAssertEqual(Apparatus.plainText(entries), "8 at last] (moved) B", "\(strategy)")
        }
    }

    func testTheSixEditionCrossPageMoveIsInTheApparatus() {
        // The proofs moved a sentence across a page; every later edition inherits the move, the typescript does not.
        let graph = Collation.variantGraph(witnesses: Samples.sixEditions)
        let moves = Apparatus.entries(from: graph).filter { $0.type == .transposition }
        XCTAssertEqual(moves.count, 1)
        XCTAssertEqual(moves.first?.lemma, "The lamps were lit along the quay one by one")
        XCTAssertEqual(moves.first?.variants.first?.sigla, ["GB1", "PR", "UNI", "US1"])
        XCTAssertFalse(moves.first?.variants.first?.sigla.contains("TS") ?? true, "the typescript keeps the order")
    }

    func testALikelyMoveIsMarkedAsPossible() {
        XCTAssertEqual(Apparatus.moveMarker(.certain), "(moved)")
        XCTAssertEqual(Apparatus.moveMarker(.likely), "(possible move)")
        // The short near-diagonal move on a long pair is `.likely` (see MoveRecoveryTests); its apparatus entry says so.
        let backbone = (0..<6000).map { "s\($0)" }
        let phrase = ["off", "the", "rocks"]
        let a = (Array(backbone[..<3001]) + phrase + Array(backbone[3001...])).joined(separator: " ")
        let b = (Array(backbone[..<3011]) + phrase + Array(backbone[3011...])).joined(separator: " ")
        let graph = Collation.variantGraph(witnesses: witnesses([("A", a), ("B", b)]))
        let moves = Apparatus.entries(from: graph).filter { $0.type == .transposition }
        XCTAssertEqual(moves.map(\.lemma), ["off the rocks"])
        XCTAssertEqual(moves.first?.variants.first?.reading, "(possible move)")
    }

    func testMovesAreOrderedAndDoNotChangeTheNodes() {
        // Adding moves to the graph must not alter its variant nodes (the JSON interchange encodes only the nodes).
        let graph = Collation.variantGraph(witnesses: witnesses([("A", "one two three four five six seven eight"),
                                                                ("B", "one six seven two three four five eight")]))
        XCTAssertFalse(graph.moves.isEmpty)
        XCTAssertTrue(graph.moves.allSatisfy { !$0.basePositions.isEmpty })
        XCTAssertEqual(graph.moves.map(\.basePositions), graph.moves.map(\.basePositions).sorted { $0.lexicographicallyPrecedes($1) })
        XCTAssertTrue(graph.variantNodes.isEmpty, "a pure move has no variant nodes")
    }
}
