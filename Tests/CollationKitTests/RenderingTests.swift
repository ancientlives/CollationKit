import XCTest
@testable import CollationKit

// Tests for the rendering layer (model, prototyped pure): accidental classification, the critical
// apparatus, and the synoptic parallel-columns table. These define HOW collation will render before the
// SwiftUI/HTML views are built in a host app.

final class RenderingTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    // MARK: accidental (variantSpelling) classification

    func testAccidentalRecordedOnlyWhenRequested() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        // Default: no accidentals reported.
        let plain = Collation.collate(base: w("GB", "the colour of the harbour"),
                                      compared: w("US", "the color of the harbor"), normalizer: norm)
        XCTAssertEqual(plain.variantSpellings, 0)
        XCTAssertTrue(plain.variations.isEmpty)

        // With recordAccidentals: colour/color and harbour/harbor surface as two variantSpellings.
        let dipl = Collation.collate(base: w("GB", "the colour of the harbour"),
                                     compared: w("US", "the color of the harbor"),
                                     normalizer: norm, recordAccidentals: true)
        XCTAssertEqual(dipl.variantSpellings, 2)
        XCTAssertTrue(dipl.variations.allSatisfy { $0.type == .variantSpelling })
        let readings = dipl.variations.map { "\($0.baseReading)/\($0.comparedReading)" }
        XCTAssertTrue(readings.contains("colour/color"))
        XCTAssertTrue(readings.contains("harbour/harbor"))
    }

    func testCapitalizationAccidentalSurfacesUnderRequest() {
        let r = Collation.collate(base: w("A", "the End of days"), compared: w("B", "the end of days"),
                                  normalizer: .substantive, recordAccidentals: true)
        XCTAssertEqual(r.variantSpellings, 1)
        XCTAssertEqual(r.variations.first?.baseReading, "End")
        XCTAssertEqual(r.variations.first?.comparedReading, "end")
    }

    // MARK: pairwise apparatus

    func testPairwiseApparatusLineFormat() {
        let r = Collation.collate(base: w("MS", "she was very happy indeed"),
                                  compared: w("TS", "she was quite content indeed"))
        let entries = Apparatus.entries(from: r)
        XCTAssertEqual(entries.count, 1)
        let line = Apparatus.plainText(entries)
        // "<pos> <lemma>] <reading> <sigil>"
        XCTAssertTrue(line.contains("very happy] quite content TS"), "got: \(line)")
    }

    func testApparatusMarksOmissionWithNullSign() {
        let r = Collation.collate(base: w("A", "the black cat sat"), compared: w("B", "the cat sat"))
        let line = Apparatus.plainText(Apparatus.entries(from: r))
        XCTAssertTrue(line.contains("black] ∅ B"), "a deletion shows the null sign for the compared reading: \(line)")
    }

    // MARK: N-witness apparatus + synopsis over the six editions

    private var editions: [Witness] {
        [
            w("MS",  "The travellers reached the grey harbour at dusk."),
            w("TS",  "The travellers reached the grey harbour at dawn."),
            w("US1", "The travelers reached the gray harbor at dawn."),
            w("UNI", "The travelers reached the gray harbor at nightfall."),
        ]
    }

    func testNWitnessApparatusGroupsVariantsBySigla() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        let graph = Collation.variantGraph(witnesses: editions, normalizer: norm)
        let entries = Apparatus.entries(from: graph)
        // The time-of-day word varies: dusk (MS) ] dawn (TS, US1) ] nightfall (UNI). One apparatus entry,
        // with the variants grouped by the witnesses that share them.
        let dusk = entries.first { $0.lemma == "dusk" }
        XCTAssertNotNil(dusk, "the 'dusk' lemma should be a point of variance")
        let dawnSigla = dusk?.variants.first { $0.reading == "dawn" }?.sigla
        XCTAssertEqual(dawnSigla, ["TS", "US1"], "dawn is shared by TS and US1")
        XCTAssertTrue(dusk!.variants.contains { $0.reading == "nightfall" && $0.sigla == ["UNI"] })
    }

    func testSynopticTableColumnsAndVariantRows() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        let order = ["MS", "TS", "US1", "UNI"]
        let graph = Collation.variantGraph(witnesses: editions, normalizer: norm)
        let table = Synopsis.table(from: graph, witnessOrder: order)

        XCTAssertEqual(table.witnessOrder, order)
        // Shared opening words ("the", "travellers", …) are agreement rows; the time word is a variant row.
        XCTAssertFalse(table.variantRows.isEmpty)
        let variantReadings = table.variantRows.flatMap { Array($0.readings.values) }
        XCTAssertTrue(variantReadings.contains("dusk"))
        XCTAssertTrue(variantReadings.contains("nightfall"))

        // The plain-text render has one header column per witness.
        let text = Synopsis.plainText(table)
        for w in order { XCTAssertTrue(text.contains(w), "header should list \(w)") }
    }

    func testSynopsisIsDeterministic() {
        let norm = Normalizer(spellingEquivalents: Normalizer.gbUSSpelling)
        let order = ["MS", "TS", "US1", "UNI"]
        let g = Collation.variantGraph(witnesses: editions, normalizer: norm)
        XCTAssertEqual(Synopsis.table(from: g, witnessOrder: order),
                       Synopsis.table(from: g, witnessOrder: order))
    }
}
