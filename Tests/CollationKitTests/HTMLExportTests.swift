import XCTest
@testable import CollationKit
@testable import CollateCLI

// MARK: - Interactive HTML viewer (BACKLOG B8) + run feedback (progress, completion, console cap)
//
// B8 ships as `collation.html` — a single self-contained page (perspective tabs per witness, alignment
// highlights by variation type, a filterable variant panel with cross-perspective hops, and the N-witness
// apparatus). These tests pin the exporter's *contract*: the payload (texts + UTF-16-offset annotations +
// apparatus) is embedded correctly and deterministically, the page is self-contained, and the CLI produces it
// everywhere it should. The interactive behaviour itself was verified in a real WebKit browser (tabs, span
// click → detail, perspective hop, apparatus view; see DEVELOPMENT_LOG 2026-07-06b).
//
// Alongside B8, the same change-set fixed the "silent hang" a full-novel run produced: progress now reports
// each stage to the ERROR channel (stdout stays clean for piped output), the run ends with an explicit
// "✓ collation finished" line, and the console text view is capped with a pointer to `--out`.

final class HTMLExportTests: XCTestCase {

    final class CapturingSink: OutputSink {
        var outLines: [String] = []; var errLines: [String] = []
        func out(_ s: String) { outLines.append(s) }
        func err(_ s: String) { errLines.append(s) }
    }

    private func makeRun(format: OutputFormat = .html) -> CollationRun {
        let ws = [Witness(id: "A", text: "the grey harbour at dusk"),
                  Witness(id: "B", text: "the gray harbour at dawn"),
                  Witness(id: "C", text: "the grey harbour at dusk tonight")]
        var opts = CLIOptions(explicitFiles: ["a", "b", "c"])
        opts.format = format
        return CollationRunner.run(opts, witnesses: ws, includeViewerPairs: true)
    }

    // MARK: the payload

    func testPayloadCarriesTextsAnnotationsAndApparatus() {
        let run = makeRun()
        let p = HTMLExport.payload(for: run)
        XCTAssertEqual(p.base, "A")
        XCTAssertEqual(p.witnesses.map { $0.id }, ["A", "B", "C"], "every witness text is embedded")
        XCTAssertTrue(p.viewerPairsAvailable)
        // Annotations are BASE-ANCHORED (one set per non-base witness), with UTF-16 offsets into the texts.
        XCTAssertTrue(p.annotations.contains { $0.witness == "B" })
        XCTAssertTrue(p.annotations.contains { $0.witness == "C" && $0.type == "insertion" },
                      "C's added word arrives as an insertion annotation")
        for a in p.annotations {
            if let from = a.base.from, let to = a.base.to {
                let text = run.witnesses[0].text as NSString
                XCTAssertTrue(from >= 0 && to <= text.length && from < to, "base offsets stay in bounds")
            }
        }
        XCTAssertFalse(p.apparatus.isEmpty, "the N-witness apparatus rides along for the graph view")
    }

    /// #2 — the visual variant-graph needs the merge SUBSTRATE the apparatus projection drops: the spine
    /// (reading order), every node (agreement compacted to a shared surface, variants carrying readings+sigla),
    /// its base-text char range for cross-linking, and the edges (spine + `isMove`). Pinned here so the block
    /// the viewer renders can't silently regress.
    func testPayloadCarriesTheGraphSubstrate() {
        let run = makeRun()
        let p = HTMLExport.payload(for: run)
        let g = try! XCTUnwrap(p.graph, "the token-graph rides along for the visual graph view")
        XCTAssertFalse(g.spine.isEmpty, "the spine (agreement backbone) is surfaced")
        XCTAssertEqual(g.nodes.count, run.tokenGraph?.nodes.count, "every graph node is surfaced")

        // Agreement nodes are compacted to just a surface (no per-witness sigla bloat); variants carry readings.
        let agree = g.nodes.filter { $0.agree != nil }
        XCTAssertTrue(agree.allSatisfy { $0.readings == nil }, "agreement nodes drop the readings array")
        XCTAssertTrue(g.nodes.contains { $0.readings != nil }, "variant nodes carry readings")
        // The grey/gray variant (base position of 'grey') exposes both readings with their sigla.
        let greyNode = g.nodes.first { ($0.readings ?? []).contains { $0.reading == "gray" } }
        XCTAssertNotNil(greyNode, "the grey→gray substitution is a variant node")
        XCTAssertEqual(greyNode?.readings?.first { $0.reading == "gray" }?.sigla, ["B"])
        XCTAssertNotNil(greyNode?.from, "a spine variant node carries its base-text char range for cross-linking")

        // C's inserted 'tonight' is an off-spine node anchored after a spine column, with an ∅ for A and B.
        let ins = g.nodes.first { $0.isInserted }
        XCTAssertNotNil(ins, "C's added word is an inserted graph node")
        XCTAssertNotNil(ins?.insertedAfterCol, "an inserted node records the spine column it follows")
    }

    /// A reordering must surface as an `isMove` edge in the graph substrate (what draws the move arc in #2).
    func testGraphSubstrateCarriesMoveEdges() {
        let ws = [Witness(id: "A", text: "the grey harbour at dusk and the ship sailed away"),
                  Witness(id: "B", text: "the gray harbour at dawn and away sailed the ship")]
        var opts = CLIOptions(explicitFiles: ["a", "b"]); opts.format = .html
        let run = CollationRunner.run(opts, witnesses: ws, includeViewerPairs: true)
        let g = try! XCTUnwrap(HTMLExport.payload(for: run).graph)
        XCTAssertTrue(g.edges.contains { $0.isMove }, "the reordering surfaces as a move edge")
    }

    /// The metadata / "what was detected" summary (tail of #5): run-wide type counts with EVERY known type
    /// present (a 0 means "checked, none found" — the reassurance the panel exists to give), witness sizes, and
    /// the merged-graph shape.
    func testPayloadCarriesTheDetectionSummary() {
        let run = makeRun()
        let s = HTMLExport.payload(for: run).summary
        for t in VariationType.allCases {
            XCTAssertNotNil(s.typeCounts[t.rawValue], "\(t.rawValue) is present even when zero — 'checked'")
        }
        XCTAssertEqual(s.typeCounts["variantSpelling"], 0, "a substantive run reports spelling explicitly as 0")
        XCTAssertGreaterThan(s.typeCounts["substitution"] ?? 0, 0, "…and the substitutions it did find")
        XCTAssertEqual(s.witnessSizes.map { $0.id }, ["A", "B", "C"], "every witness's size is reported")
        XCTAssertTrue(s.witnessSizes.allSatisfy { $0.chars > 0 && $0.tokens > 0 })
        XCTAssertGreaterThan(s.spineLength, 0, "the graph shape rides along")
        XCTAssertGreaterThanOrEqual(s.variantNodes, 1, "…including the variant-node count")
    }

    /// A pure insertion has no base-side range (that is what the viewer's perspective hop is for): the base
    /// side must be nil-offsets with the ∅-style empty reading, and the witness side must carry the range.
    func testInsertionAnnotationSidesMatchTheHopContract() {
        let run = makeRun()
        let ins = HTMLExport.payload(for: run).annotations.first { $0.witness == "C" && $0.type == "insertion" }
        XCTAssertNotNil(ins)
        XCTAssertNil(ins?.base.from, "an insertion has no base span — the panel offers the hop instead")
        XCTAssertNotNil(ins?.comp.from, "…and a witness-side span to hop to")
    }

    // MARK: the page

    func testHTMLIsSelfContainedEscapedAndDeterministic() {
        let run = makeRun()
        let html = HTMLExport.html(run)
        XCTAssertTrue(html.contains("<script type=\"application/json\" id=\"data\">"), "payload embedded")
        XCTAssertFalse(html.contains("http://"), "no external resources — the page must work offline")
        XCTAssertFalse(html.contains("https://"), "no external resources — the page must work offline")
        XCTAssertEqual(html, HTMLExport.html(run), "deterministic — snapshot-diffable like every exporter")

        // A witness text containing `</script>` must not terminate the data block.
        let hostile = [Witness(id: "A", text: "x </script><b>pwn</b> y"), Witness(id: "B", text: "x z y")]
        var opts = CLIOptions(explicitFiles: ["a", "b"]); opts.format = .html
        let hostileRun = CollationRunner.run(opts, witnesses: hostile, includeViewerPairs: true)
        let hostileHTML = HTMLExport.html(hostileRun)
        let dataBlock = hostileHTML.components(separatedBy: "<script type=\"application/json\" id=\"data\">")[1]
            .components(separatedBy: "</script>")[0]
        XCTAssertTrue(dataBlock.contains("\\u003c") && dataBlock.contains("script\\u003e"),
                      "embedded `<` and `>` are \\u-escaped in the JSON block")
        XCTAssertFalse(dataBlock.contains("<"), "no raw `<` at all, so the data block cannot be terminated or re-moded")
    }

    // MARK: CLI integration

    func testExportAlwaysIncludesTheViewer() {
        for format in [OutputFormat.text, .json, .csv, .html] {
            var run = makeRun(); _ = run
            run = makeRun(format: format)
            let names = Exporter.files(for: run).map { $0.name }
            XCTAssertTrue(names.contains("collation.html"),
                          "\(format.rawValue): collation.html is always exported (B8)")
            XCTAssertTrue(names.contains("collation.json"), "\(format.rawValue): the interchange too")
        }
    }

    func testConsoleHTMLFormatPrintsThePage() throws {
        let dir = NSTemporaryDirectory() + "html-fmt-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "alpha beta gamma".write(toFile: dir + "/A.txt", atomically: true, encoding: .utf8)
        try "alpha delta gamma".write(toFile: dir + "/B.txt", atomically: true, encoding: .utf8)
        let sink = CapturingSink()
        let code = CollateCLI.main(["run", dir + "/A.txt", dir + "/B.txt", "--format", "html"], sink: sink)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(sink.outLines.joined().contains("<!DOCTYPE html>"), "html format streams the page")
    }

    // MARK: progress + completion + console cap (the full-text "hang" fix)

    func testRunReportsProgressAndFinishesExplicitly() throws {
        let dir = NSTemporaryDirectory() + "progress-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "one two three".write(toFile: dir + "/A.txt", atomically: true, encoding: .utf8)
        try "one two four".write(toFile: dir + "/B.txt", atomically: true, encoding: .utf8)
        let sink = CapturingSink()
        let code = CollateCLI.main(["run", dir + "/A.txt", dir + "/B.txt"], sink: sink)
        XCTAssertEqual(code, 0)
        let err = sink.errLines.joined(separator: "\n")
        XCTAssertTrue(err.contains("witnesses loaded"), "progress: witnesses announced")
        XCTAssertTrue(err.contains("collating pair 1/1"), "progress: each pair announced as it starts")
        XCTAssertTrue(err.contains("building the N-witness variant graph"), "progress: graph stage announced")
        XCTAssertTrue(err.contains("merging witness 1/1 onto the spine"),
                      "progress: the graph build reports each witness as it folds (not a single frozen line)")
        XCTAssertTrue(err.contains("finalising the graph"), "progress: the graph finalisation is announced")
        XCTAssertTrue(err.contains("✓ collation finished"), "an explicit completion line")
        XCTAssertTrue(err.contains("variant(s)"), "…with counts")
        // Progress must NOT pollute stdout (piped output stays clean).
        XCTAssertFalse(sink.outLines.joined().contains("✓ collation finished"))
    }

    func testGraphBuildReportsEveryWitnessInOrder() throws {
        // With N witnesses the graph merge folds N-1 of them onto the spine; each must be announced, in order,
        // so a long full-text build is visibly progressing instead of a single line that looks frozen.
        let dir = NSTemporaryDirectory() + "graphprog-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "alpha beta gamma delta".write(toFile: dir + "/A.txt", atomically: true, encoding: .utf8)
        try "alpha BETA gamma delta".write(toFile: dir + "/B.txt", atomically: true, encoding: .utf8)
        try "alpha beta GAMMA delta".write(toFile: dir + "/C.txt", atomically: true, encoding: .utf8)
        let sink = CapturingSink()
        let code = CollateCLI.main(["run", dir + "/A.txt", dir + "/B.txt", dir + "/C.txt"], sink: sink)
        XCTAssertEqual(code, 0)
        let err = sink.errLines.joined(separator: "\n")
        XCTAssertTrue(err.contains("merging witness 1/2 onto the spine"), "first fold announced")
        XCTAssertTrue(err.contains("merging witness 2/2 onto the spine"), "second fold announced")
        guard let i1 = err.range(of: "merging witness 1/2"),
              let i2 = err.range(of: "merging witness 2/2") else { return XCTFail("both folds present") }
        XCTAssertTrue(i1.lowerBound < i2.lowerBound, "witnesses are reported in order")
        // The runner indents the graph sub-steps under the stage header.
        XCTAssertTrue(err.contains("  merging witness"), "graph sub-steps are indented under the stage header")
    }

    func testConsoleTextIsCappedWithAPointerToExport() {
        // A run whose combined text exceeds the cap must truncate with explicit guidance; a small run is full.
        let small = makeRun(format: .text)
        XCTAssertFalse(Exporter.consolePreview(small).contains("truncated"),
                       "small runs print in full")
        let big = Exporter.consolePreview(small, maxLines: 3)
        XCTAssertTrue(big.contains("console preview truncated at 3 lines"), "over the cap → truncated")
        XCTAssertTrue(big.contains("--out <dir>"), "…with the export pointer")
        XCTAssertTrue(big.contains("collation.html"), "…naming the interactive viewer")
    }
}
