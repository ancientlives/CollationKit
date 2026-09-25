import XCTest
@testable import CollationKit

// MARK: - N-witness graph insertion anchoring (BACKLOG B6c)
//
// Before B6c, a PURE insertion (text a witness adds where the base has nothing) was caught by the pairwise
// collation but DROPPED from the N-witness variant graph — so the apparatus/synopsis printed "(no points of
// variance)" for added stanzas. B6c anchors each insertion between two base positions via its insert-after
// anchor, so it becomes an *inserted node*: the base (and any witness without the text) reads `∅`, the
// carriers read the added text, and the node is a variant.
//
// These lock that behaviour directly (the conformance goldens also pin it end-to-end via the JSON, e.g.
// cases 02, 18, 23, 25); here we assert the graph/apparatus/synopsis models a consumer actually reads.

final class GraphInsertionTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    /// A witness inserts a phrase the base lacks → one inserted node in the graph, anchored after the base
    /// word it follows, with the base reading `∅` and the carrier reading the added text.
    func testInsertionBecomesAnchoredGraphNode() {
        let base = w("A", "I celebrate myself")
        let ins  = w("B", "I celebrate myself and sing myself")
        let graph = Collation.variantGraph(witnesses: [base, ins])

        let inserted = graph.nodes.filter { $0.isInserted }
        XCTAssertEqual(inserted.count, 1, "the added phrase is one inserted node")
        let node = inserted[0]
        XCTAssertEqual(node.basePosition, -1, "an inserted node has no base position")
        XCTAssertNotNil(node.insertedAfter, "it must carry an insert-after anchor")
        // The carrier reads the added text; the base omits it (∅).
        let carriers = node.readings["and sing myself"]
        XCTAssertEqual(carriers, ["B"], "B carries the inserted text")
        XCTAssertEqual(node.readings["∅"], ["A"], "the base omits the insertion → ∅")
        XCTAssertTrue(node.isVariant, "text-vs-∅ is a point of variance")
    }

    /// The inserted node renders as an apparatus line with an empty (`∅`) lemma, typed as an insertion.
    func testInsertionRendersAsInsertionApparatusEntry() {
        let graph = Collation.variantGraph(witnesses: [
            w("A", "the cat sat"),
            w("B", "the cat quietly sat"),
        ])
        let entries = Apparatus.entries(from: graph)
        let ins = entries.first { $0.type == .insertion }
        XCTAssertNotNil(ins, "the added word is an insertion apparatus entry")
        XCTAssertEqual(ins?.lemma, "∅", "the base omits the inserted text, so the lemma is ∅")
        XCTAssertEqual(ins?.variants.first { $0.reading == "quietly" }?.sigla, ["B"])
    }

    /// The synopsis shows an inserted row: the carrier column has the text, every other column shows `∅`.
    func testInsertionAppearsInSynopsisWithOmissionElsewhere() {
        let order = ["A", "B", "C"]
        let graph = Collation.variantGraph(witnesses: [
            w("A", "alpha beta"),
            w("B", "alpha inserted beta"),
            w("C", "alpha beta"),
        ])
        let table = Synopsis.table(from: graph, witnessOrder: order)
        let row = table.variantRows.first { $0.readings["B"] == "inserted" }
        XCTAssertNotNil(row, "B's inserted word is a variant row")
        XCTAssertEqual(row?.readings["A"], "∅", "A omits it")
        XCTAssertEqual(row?.readings["C"], "∅", "C omits it")
    }

    /// Two insertions at DIFFERENT anchors both appear, each after the base word it follows — the graph stays
    /// text-ordered (base positions, with each inserted node right after its anchor).
    func testMultipleInsertionsOrderByAnchor() {
        let graph = Collation.variantGraph(witnesses: [
            w("A", "one two three"),
            w("B", "one X two three Y"),
        ])
        let inserted = graph.nodes.filter { $0.isInserted }
        XCTAssertEqual(inserted.count, 2, "two separate insertions → two inserted nodes")
        // Their anchors are strictly increasing and each sits after an earlier base position.
        let anchors = inserted.map { $0.insertedAfter ?? Int.min }
        XCTAssertEqual(anchors, anchors.sorted(), "inserted nodes stay in text order by anchor")
        XCTAssertLessThan(anchors[0], anchors[1], "the two insertions anchor at different base positions")
    }

    /// Determinism: the same witness set yields byte-identical graphs (guards the sort keys for inserted nodes).
    func testInsertionGraphIsDeterministic() {
        let ws = [w("A", "a b c"), w("B", "a b inserted c"), w("C", "a b c")]
        XCTAssertEqual(Collation.variantGraph(witnesses: ws), Collation.variantGraph(witnesses: ws))
    }
}
