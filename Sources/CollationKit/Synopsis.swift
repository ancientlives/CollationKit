import Foundation

// MARK: - Synoptic / parallel-segmentation rendering (model, prototyped pure)
//
// The side-by-side display scholars expect: witnesses in parallel columns with aligned rows, so the eye can
// scan a row and see each witness's reading at that point. Built from the N-witness variant graph — each
// base position is a row; each witness's reading fills its column (or "∅" where that witness omits it).
// Rows where the witnesses disagree are flagged `isVariant` so the UI can highlight them.
//
// Plain-text rendering here (a fixed-width table) keeps it testable; a host app's view maps the same
// `SynopticTable` to a SwiftUI grid / HTML table. The model/format split is deliberate (one source → many
// renderings), the same abstraction as the apparatus.

public struct SynopticRow: Equatable {
    public let position: Int
    /// witness id → its reading at this row ("∅" = omitted by that witness).
    public let readings: [String: String]
    public var isVariant: Bool { Set(readings.values).count > 1 }
}

public struct SynopticTable: Equatable {
    public let witnessOrder: [String]      // column order (base first, then the rest as supplied)
    public let rows: [SynopticRow]
    public var variantRows: [SynopticRow] { rows.filter { $0.isVariant } }

    public init(witnessOrder: [String], rows: [SynopticRow]) {
        self.witnessOrder = witnessOrder
        self.rows = rows
    }

    /// The same table keeping only the rows where witnesses disagree — a compact apparatus-style view.
    public var variantsOnly: SynopticTable { SynopticTable(witnessOrder: witnessOrder, rows: variantRows) }
}

public enum Synopsis {

    /// Build a synoptic table from a variant graph. `witnessOrder` fixes the column order (typically the
    /// editorial sequence MS → TS → … → Uniform); any witness not present at a row is shown as "∅".
    public static func table(from graph: Collation.VariantGraph, witnessOrder: [String]) -> SynopticTable {
        // Preserve the graph's own text order (base positions with each inserted node right after its anchor);
        // `graph.nodes` is already sorted that way, so index-preserving enumeration keeps inserted rows in place
        // rather than collapsing them all to position -1. (B6c: inserted rows show text some witnesses added.)
        let rows = graph.nodes.map { node -> SynopticRow in
            var readings: [String: String] = [:]
            // Invert reading → sigla into siglum → reading.
            for (reading, sigla) in node.readings {
                for s in sigla { readings[s] = reading }
            }
            // Any column with no reading at this node omitted the word here.
            for w in witnessOrder where readings[w] == nil { readings[w] = "∅" }
            // Row position tracks the graph's ordering: a base index, or (for an inserted node) the anchor it
            // follows. `graph.nodes` is already in text order, so we keep that order rather than re-sorting by
            // this position (inserted nodes share -1 as basePosition, which would otherwise collapse them).
            let position = node.isInserted ? (node.insertedAfter ?? -1) : node.basePosition
            return SynopticRow(position: position, readings: readings)
        }
        return SynopticTable(witnessOrder: witnessOrder, rows: rows)
    }

    /// Render as a fixed-width text table (one column per witness). For diagnostics/tests and a quick CLI
    /// preview of what a host app's columns would show.
    public static func plainText(_ table: SynopticTable, columnWidth: Int = 14) -> String {
        func cell(_ s: String) -> String {
            let t = s.count > columnWidth ? String(s.prefix(columnWidth - 1)) + "…" : s
            return t.padding(toLength: columnWidth, withPad: " ", startingAt: 0)
        }
        var lines: [String] = []
        lines.append(table.witnessOrder.map(cell).joined(separator: "| "))
        lines.append(String(repeating: "-", count: max(0, (columnWidth + 2) * table.witnessOrder.count - 2)))
        for row in table.rows {
            lines.append(table.witnessOrder.map { cell(row.readings[$0] ?? "∅") }.joined(separator: "| "))
        }
        return lines.joined(separator: "\n")
    }
}
