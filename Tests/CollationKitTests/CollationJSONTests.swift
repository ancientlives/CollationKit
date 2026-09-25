import XCTest
@testable import CollationKit

// The cross-language JSON interchange: a stable, web-friendly wire schema decoupled from the engine's Swift
// types. These pin the shape (so a WASM/web client or a comparison harness can rely on it) and that it
// round-trips and is deterministic.

final class CollationJSONTests: XCTestCase {

    private func w(_ id: String, _ t: String) -> Witness { Witness(id: id, text: t) }

    func testPairwiseDTOCapturesTypedLocatedVariants() {
        let r = Collation.collate(base: w("A", "the quick brown fox"), compared: w("B", "the quick red fox"))
        let dto = CollationJSON.dto(r)
        XCTAssertEqual(dto.schemaVersion, CollationJSON.schemaVersion)
        XCTAssertEqual(dto.base, "A"); XCTAssertEqual(dto.compared, "B")
        XCTAssertEqual(dto.counts["substitution"], 1)
        let v = dto.variations.first { $0.type == .substitution }!
        XCTAssertEqual(v.baseReading, "brown")
        XCTAssertEqual(v.comparedReading, "red")
        // Range reshaped to explicit half-open { from, to }.
        XCTAssertNotNil(v.baseTokens)
        XCTAssertEqual(v.baseTokens!.to - v.baseTokens!.from, 1)
        // Location carries the 1-based citation string so a JS client needn't re-derive it.
        XCTAssertEqual(v.baseLocation?.cite, "p.1 · line 1 · word 3")
    }

    func testRoundTripThroughJSON() throws {
        let r = Collation.collate(base: w("A", "she was very happy indeed"),
                                  compared: w("B", "she was quite content indeed"))
        let json = CollationJSON.string(r)
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CollationJSON.PairwiseDTO.self, from: data)
        XCTAssertEqual(decoded, CollationJSON.dto(r), "DTO survives encode→decode unchanged")
    }

    func testVariationTypeEncodesAsAStableStringTag() {
        let r = Collation.collate(base: w("A", "the black cat"), compared: w("B", "the cat"))
        let json = CollationJSON.string(r, pretty: false)
        XCTAssertTrue(json.contains("\"deletion\""), "the type encodes as its string tag, not an ordinal")
    }

    func testGraphDTOReadingsAreSortedAndDeterministic() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        let witnesses = [w("MS", "the grey harbour at dusk"),
                         w("TS", "the grey harbour at dawn"),
                         w("US1", "the gray harbor at dawn")]
        let g = Collation.variantGraph(witnesses: witnesses, normalizer: norm)
        let d1 = CollationJSON.dto(g)
        let d2 = CollationJSON.dto(g)
        XCTAssertEqual(d1, d2, "graph DTO is deterministic")
        // Each node's readings are sorted by reading; each reading's witnesses are sorted.
        for node in d1.nodes {
            XCTAssertEqual(node.readings.map { $0.reading }, node.readings.map { $0.reading }.sorted())
            for r in node.readings { XCTAssertEqual(r.witnesses, r.witnesses.sorted()) }
        }
    }

    func testJSONStringIsByteStableAcrossCalls() {
        // Sorted keys + sorted readings ⇒ identical bytes each run (good for snapshot tests / cross-language
        // diffing against another collator's output).
        let r = Collation.collate(base: w("A", "alpha beta gamma"), compared: w("B", "alpha BETA gamma"))
        XCTAssertEqual(CollationJSON.string(r), CollationJSON.string(r))
    }
}
