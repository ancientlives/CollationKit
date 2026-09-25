import Foundation

// MARK: - Critical apparatus rendering (model, prototyped pure)
//
// Turns collation results into the *apparatus criticus* a scholar reads: a base ("copy-text") reading with,
// for each point of variance, the lemma followed by the variant readings and the sigla (witness ids) that
// carry them. This is the printed-critical-edition convention (e.g. "12 colour] color US1").
//
// Rendered as PLAIN TEXT here so it is fully unit-testable and host-agnostic; a host app's view maps the
// same `ApparatusEntry` model to SwiftUI / the HTML export. Keeping the model separate from any one output
// format is the abstraction that lets the apparatus drive footnotes, a side panel, or an exported page
// from one source.

/// One entry in the apparatus: a lemma (the base reading at a point of variance) and the witness readings
/// that diverge from it. `position` orders entries through the text (token index in the base, or the
/// N-witness graph's base position).
public struct ApparatusEntry: Equatable {
    public let position: Int
    public let lemma: String                       // the base/copy-text reading ("∅" if base omits it)
    public let type: VariationType
    /// reading → sigla carrying it (excluding the base's own reading). "∅" denotes omission.
    public let variants: [(reading: String, sigla: [String])]

    public static func == (l: ApparatusEntry, r: ApparatusEntry) -> Bool {
        l.position == r.position && l.lemma == r.lemma && l.type == r.type
            && l.variants.map { [$0.reading] + $0.sigla } == r.variants.map { [$0.reading] + $0.sigla }
    }
}

public enum Apparatus {

    // MARK: pairwise apparatus (base vs. one compared witness)

    /// Build apparatus entries from a pairwise collation. The compared witness's sigil labels each variant.
    public static func entries(from result: CollationResult) -> [ApparatusEntry] {
        result.variations.compactMap { v in
            let pos = v.baseTokenRange?.lowerBound ?? v.comparedTokenRange?.lowerBound ?? 0
            let lemma = v.baseReading.isEmpty ? "∅" : v.baseReading
            let reading = v.comparedReading.isEmpty ? "∅" : v.comparedReading
            return ApparatusEntry(position: pos, lemma: lemma, type: v.type,
                                  variants: [(reading: reading, sigla: [result.compared])])
        }
    }

    // MARK: N-witness apparatus (from the variant graph)

    /// Build apparatus entries from an N-witness variant graph: each variant node becomes one entry whose
    /// lemma is the base witness's reading and whose variants are the OTHER readings + their sigla.
    public static func entries(from graph: Collation.VariantGraph) -> [ApparatusEntry] {
        graph.variantNodes.map { node in
            // The lemma is the reading carried by the base witness (if any); else the most-attested reading.
            // For an INSERTED node (B6c) the base has no reading here, so the lemma is `∅` and the entry is an
            // insertion, not a substitution — the classic "lemma is empty, witnesses add text" apparatus line.
            let baseReading = node.readings.first { $0.value.contains(graph.baseID) }?.key
            let lemma = baseReading ?? (node.isInserted ? "∅"
                        : node.readings.max { $0.value.count < $1.value.count }?.key ?? "∅")
            let variants = node.readings
                .filter { $0.key != lemma }
                .map { (reading: $0.key, sigla: $0.value.sorted()) }
                .sorted { $0.reading < $1.reading }
            // Inserted nodes sort after their anchor base position; use a stable ordering key that keeps them
            // adjacent to (just after) that anchor. `basePosition` is -1 for inserted nodes, so key off the
            // anchor when inserted. (Rendering sorts by `position`; ties keep insertion output stable.)
            let position = node.isInserted ? (node.insertedAfter ?? -1) : node.basePosition
            return ApparatusEntry(position: position, lemma: lemma,
                                  type: node.isInserted ? .insertion : .substitution, variants: variants)
        }
    }

    // MARK: text rendering

    /// Render entries as a plain-text apparatus, one line per entry, in the classic
    /// "<pos> <lemma>] <reading> <sigla>; <reading> <sigla>" shape.
    public static func plainText(_ entries: [ApparatusEntry]) -> String {
        entries.sorted { $0.position < $1.position }.map { e in
            let rhs = e.variants.map { v in
                "\(v.reading) \(v.sigla.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
            }.joined(separator: "; ")
            return "\(e.position) \(e.lemma)] \(rhs)"
        }.joined(separator: "\n")
    }
}
