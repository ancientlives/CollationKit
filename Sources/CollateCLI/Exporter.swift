import CollationKit
import Foundation

// MARK: - Rendering + export (BACKLOG B9, CLI_PLAN §6)
//
// Turns a `CollationRun` into strings (per format) and writes them to an output directory. The renderers reuse
// the engine's own render models (`Report`, `Apparatus`, `Synopsis`, `CollationJSON`) — the CLI adds no new
// rendering logic, only file layout and the CSV/manifest shapes. All output is deterministic (sorted/stable),
// so it can be snapshot-tested and diffed, matching the conformance corpus's ethos.

public enum Exporter {

    // MARK: console / text sections (the existing engine renderers)

    /// The located variant report for every successive pair, concatenated (the same text `collate-demo` shows).
    public static func locatedReport(_ run: CollationRun) -> String {
        run.pairs.map { Report.located($0) }.joined(separator: "\n\n")
    }

    /// The N-witness critical apparatus (or a clear empty-state line).
    public static func apparatus(_ run: CollationRun) -> String {
        let entries = Apparatus.entries(from: run.graph)
        return entries.isEmpty ? "(no points of variance)" : Apparatus.plainText(entries)
    }

    /// The synoptic parallel columns for the variant rows (or a clear empty-state line).
    public static func synopsis(_ run: CollationRun) -> String {
        let table = Synopsis.table(from: run.graph, witnessOrder: run.witnessOrder)
        return table.variantRows.isEmpty ? "(witnesses agree everywhere)"
                                         : Synopsis.plainText(table.variantsOnly, columnWidth: 14)
    }

    /// A plain-prose NARRATIVE of the collation — how, where, and how much each witness differs from the base,
    /// plus an alignment-quality verdict (the same story the interactive dashboard tells, in words). Uses the
    /// base-anchored pairs when available (so every non-base witness is described against the base); falls back to
    /// the successive pairs. One paragraph per compared witness.
    public static func narrative(_ run: CollationRun) -> String {
        let pairs = run.basePairs.isEmpty ? run.pairs : run.basePairs
        guard !pairs.isEmpty else { return "(nothing to summarise)" }
        let textByID = Dictionary(run.witnesses.map { ($0.id, $0.text) }, uniquingKeysWith: { a, _ in a })
        return pairs.map { pair -> String in
            let baseText = textByID[pair.base] ?? "", compText = textByID[pair.compared] ?? ""
            return CollationNarrative.summary(pair, base: baseText, compared: compText)
        }.joined(separator: "\n\n")
    }

    /// A single combined text rendering (narrative + report + apparatus + synopsis) for the console.
    public static func combinedText(_ run: CollationRun) -> String {
        func rule(_ t: String) -> String { String(repeating: "═", count: 78) + "\n" + t + "\n" + String(repeating: "═", count: 78) }
        return [
            rule("SUMMARY  (base = \(run.baseID))"), narrative(run),
            "", rule("LOCATED VARIANT REPORT (successive pairs)"), locatedReport(run),
            "", rule("CRITICAL APPARATUS  (base = \(run.baseID))"), apparatus(run),
            "", rule("SYNOPTIC COLUMNS  (rows where witnesses differ)"), synopsis(run),
        ].joined(separator: "\n")
    }

    /// How many lines the CONSOLE text view shows before truncating. A full-novel collation renders millions
    /// of characters; dumping them to a terminal takes minutes and reads as a hang (exactly what the Verne
    /// full texts produced). File export (`--out`) always writes the complete report.
    public static let consoleLineCap = 2_000

    /// The console-safe text view: the full combined report when it is small, else the first `maxLines`
    /// lines with an explicit truncation notice pointing at `--out` (which also writes the interactive
    /// `collation.html`). Deterministic; used only for console output, never for files.
    public static func consolePreview(_ run: CollationRun, maxLines: Int = consoleLineCap) -> String {
        let full = combinedText(run)
        let lines = full.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maxLines else { return full }
        let shown = lines.prefix(maxLines).joined(separator: "\n")
        return shown + """


        … console preview truncated at \(maxLines) lines (\(lines.count) total, \
        \(run.totalPairVariants) variant(s) across \(run.pairs.count) pair(s)).
        Export the complete report with:  --out <dir>   (writes located-report.txt, apparatus.txt,
        synopsis.txt, collation.json, and the interactive collation.html viewer)
        """
    }

    // MARK: JSON (the always-exported interchange)

    /// The `{ graph, pairs }` interchange — **byte-identical to what the conformance corpus pins and
    /// `collate-demo --json` emits** (CLI_PLAN §0 rule 3: a CLI export and a golden are the same artifact),
    /// now encoded from the run's ALREADY-COMPUTED graph + pairs. The old witness-based call silently
    /// re-ran the whole engine (every pair + the graph) just to encode results the runner already had — on a
    /// full-novel set that doubled the run (and in a debug build turned it into a perceived hang). The
    /// byte-identity tie survives because the runner computes graph/pairs with exactly the options the
    /// witness-based path would use — enforced by `testJSONExportEqualsConformanceGolden`.
    public static func json(_ run: CollationRun) -> String {
        CollationJSON.outputString(graph: run.graph, pairs: run.pairs)
    }

    // MARK: CSV (phase 2 — one row per variant, RFC 4180 quoting)

    /// One row per variant across all pairs, for spreadsheet/data use (CLI_PLAN §6). Deterministic column order.
    public static func csv(_ run: CollationRun) -> String {
        var rows: [String] = [
            "pair_base,pair_compared,type,confidence,base_reading,compared_reading,base_cite,compared_cite,crosses_page"
        ]
        for pair in run.pairs {
            for v in pair.variations {
                let cols = [
                    pair.base, pair.compared, v.type.rawValue, v.confidence.rawValue,
                    v.baseReading, v.comparedReading,
                    v.baseLocation?.human ?? "", v.comparedLocation?.human ?? "",
                    v.crossesPage ? "true" : "false",
                ]
                rows.append(cols.map(csvQuote).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    /// RFC 4180 quoting: wrap in quotes and double any embedded quote when the field contains a comma, quote,
    /// or newline. Deterministic and reversible.
    static func csvQuote(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: manifest (self-describing run record)

    /// A small manifest recording the run so an exported result set is self-describing (CLI_PLAN §6) — the same
    /// ethos as the benchmark header. Deterministic except the timestamp, which the caller may omit for tests.
    public static func manifest(_ run: CollationRun, timestamp: String?) -> String {
        let o = run.options
        var lines = [
            "# CollationKit run manifest",
            "engine_schema_version: \(CollationJSON.schemaVersion)",
            "base: \(run.baseID)",
            "witness_order: \(run.witnessOrder.joined(separator: ", "))",
            "mode: \(o.mode.rawValue)",
            "record_accidentals: \(o.effectiveRecordAccidentals)",
            "record_punctuation: \(o.effectiveRecordPunctuation)",
            "strategy: \(o.strategy.rawValue)",
            "scoring: \(o.scoring.rawValue)",
            "lexicon: \(o.lexiconPath ?? "none")",
            "format: \(o.format.rawValue)",
        ]
        if let ts = timestamp { lines.append("generated: \(ts)") }
        return lines.joined(separator: "\n")
    }

    // MARK: writing files

    /// A file the exporter will write: relative name + contents.
    public struct File: Equatable { public let name: String; public let contents: String }

    /// The files a run exports for the chosen format, as LAZY renderers — each `render()` is invoked only
    /// when the file is produced, so `write` can announce a file BEFORE its (potentially slow, multi-MB)
    /// render rather than after all of them. JSON + manifest + the interactive HTML viewer (B8) are ALWAYS
    /// included (CLI_PLAN §6): whatever format the user picks, `collation.json` makes the run
    /// reproducible/consumable downstream, and `collation.html` is the explorable result they can open.
    static func fileRenderers(for run: CollationRun,
                              timestamp: String? = nil) -> [(name: String, render: () -> String)] {
        var out: [(name: String, render: () -> String)] = []
        switch run.options.format {
        case .text:
            out.append(("located-report.txt", { locatedReport(run) }))
            out.append(("apparatus.txt", { apparatus(run) }))
            out.append(("synopsis.txt", { synopsis(run) }))
        case .csv:
            out.append(("variants.csv", { csv(run) }))
        case .json, .html:
            break   // both are written below regardless.
        }
        out.append(("summary.txt", { narrative(run) }))          // always — the plain-prose story of the collation
        out.append(("collation.json", { json(run) }))            // always
        out.append(("collation.html", { HTMLExport.html(run) })) // always (B8)
        out.append(("manifest.txt", { manifest(run, timestamp: timestamp) }))
        return out
    }

    /// The eager form of `fileRenderers` (tests and small runs).
    public static func files(for run: CollationRun, timestamp: String? = nil) -> [File] {
        fileRenderers(for: run, timestamp: timestamp).map { File(name: $0.name, contents: $0.render()) }
    }

    /// Check, before any collation work, that `rawDir` can be created and written to: create it (with
    /// intermediates) and write and remove a probe file. Throws the same `.io` error `write` would.
    public static func preflight(directory rawDir: String) throws {
        let dir = Paths.expand(rawDir)
        let fm = FileManager.default
        do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        catch { throw CLIError(.io, "cannot create output directory \(dir): \(error.localizedDescription)") }
        let probe = (dir as NSString).appendingPathComponent(".collate-write-test")
        do { try "".write(toFile: probe, atomically: false, encoding: .utf8); try fm.removeItem(atPath: probe) }
        catch { throw CLIError(.io, "cannot write to output directory \(dir): \(error.localizedDescription)") }
    }

    /// Write the export files into `dir` (created if needed; `~` expanded — a menu-typed `~/out` must not
    /// become a literal `./~` directory). Returns the paths written. `progress` (optional) reports each file
    /// BEFORE it renders — the renders are the slow part on large runs, so a silent loop reads as a hang.
    /// Fails clearly on IO errors. Overwrite-confirmation is Stage B; here we overwrite.
    @discardableResult
    public static func write(_ run: CollationRun, toDirectory rawDir: String, timestamp: String? = nil,
                             progress: ((String) -> Void)? = nil) throws -> [String] {
        let dir = Paths.expand(rawDir)
        let fm = FileManager.default
        do { try fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
        catch { throw CLIError(.io, "cannot create output directory \(dir): \(error.localizedDescription)") }
        var written: [String] = []
        for f in fileRenderers(for: run, timestamp: timestamp) {
            progress?("writing \(f.name) …")
            let path = (dir as NSString).appendingPathComponent(f.name)
            do { try (f.render() + "\n").write(toFile: path, atomically: true, encoding: .utf8) }
            catch { throw CLIError(.io, "cannot write \(path): \(error.localizedDescription)") }
            written.append(path)
        }
        return written
    }
}
