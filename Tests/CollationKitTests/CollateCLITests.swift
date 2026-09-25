import XCTest
@testable import CollateCLI
@testable import CollationKit

// MARK: - CLI harness tests (BACKLOG B9, CLI_PLAN §8)
//
// The reason `CollateCLI` is a separate, terminal-free core: its parsing, discovery, exporters, and dispatch
// are the parts most worth testing, and they must be testable WITHOUT a real TTY. These drive the core with
// plain values + a temp directory + an in-memory `OutputSink`. The load-bearing test ties the CLI to the
// conformance corpus: the CLI's JSON export equals the committed golden for the same witness set (CLI_PLAN §0
// rule 3 — a CLI export and a golden are the same artifact).

final class CollateCLITests: XCTestCase {

    // An in-memory sink that records what the CLI would print.
    final class CapturingSink: OutputSink {
        var outLines: [String] = []; var errLines: [String] = []
        func out(_ s: String) { outLines.append(s) }
        func err(_ s: String) { errLines.append(s) }
    }

    // MARK: option parsing & validation

    func testParseRunFlagsIntoOptions() throws {
        let o = try CLIParser.parseRun(["--dir", "ed", "--all", "--base", "MS", "--order", "MS,TS,PR",
                                        "--diplomatic", "--format", "json", "--out", "res"])
        XCTAssertEqual(o.directory, "ed")
        XCTAssertTrue(o.useAll)
        XCTAssertEqual(o.base, "MS")
        XCTAssertEqual(o.order, ["MS", "TS", "PR"])
        XCTAssertEqual(o.mode, .diplomatic)
        XCTAssertEqual(o.format, .json)
        XCTAssertEqual(o.outDir, "res")
        // The diplomatic preset turns both accidental overlays on.
        XCTAssertTrue(o.effectiveRecordAccidentals)
        XCTAssertTrue(o.effectiveRecordPunctuation)
    }

    func testUnknownFlagIsUsageError() {
        XCTAssertThrowsError(try CLIParser.parseRun(["--nope"])) { e in
            XCTAssertEqual((e as? CLIError)?.kind, .usage)
        }
    }

    func testBaseNotInOrderIsUsageError() {
        var o = CLIOptions(explicitFiles: ["a.txt"]); o.base = "ZZ"; o.order = ["A", "B"]
        XCTAssertThrowsError(try CLIParser.validate(o)) { e in
            XCTAssertEqual((e as? CLIError)?.kind, .usage)
        }
    }

    func testNoWitnessSourceIsUsageError() {
        XCTAssertThrowsError(try CLIParser.validate(CLIOptions())) { e in
            XCTAssertEqual((e as? CLIError)?.kind, .usage)
        }
    }

    func testBadLinesPerPageIsUsageError() {
        XCTAssertThrowsError(try CLIParser.parseRun(["--lines-per-page", "0"]))
        XCTAssertThrowsError(try CLIParser.parseRun(["--lines-per-page", "x"]))
    }

    // MARK: witness discovery + loading

    private func tempDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory() + "collate-cli-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(toFile: (dir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testDiscoverFindsTextFilesSortedAndSkipsOthers() throws {
        let dir = try tempDir(["B.txt": "b", "A.md": "a", "notes.pdf": "x", "C.txt": "c"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let found = try WitnessLoader.discover(inDirectory: dir)
        XCTAssertEqual(found.map { $0.siglum }, ["A", "B", "C"], "sorted, .pdf skipped, stems as sigla")
    }

    func testLoadAppliesOrderAndBase() throws {
        let dir = try tempDir(["MS.txt": "the cat sat", "TS.txt": "the cat sat still", "PR.txt": "the dog sat"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var o = CLIOptions(directory: dir); o.order = ["MS", "TS", "PR"]; o.base = "PR"
        let ws = try WitnessLoader.load(o)
        XCTAssertEqual(ws.map { $0.id }, ["PR", "MS", "TS"], "base promoted to front, rest keep order")
    }

    func testLoadFewerThanTwoWitnessesFails() throws {
        let dir = try tempDir(["only.txt": "hello"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        XCTAssertThrowsError(try WitnessLoader.load(CLIOptions(directory: dir))) { e in
            XCTAssertEqual((e as? CLIError)?.kind, .witnesses)
        }
    }

    // MARK: exporters

    func testCSVQuotingIsRFC4180() {
        XCTAssertEqual(Exporter.csvQuote("plain"), "plain")
        XCTAssertEqual(Exporter.csvQuote("a,b"), "\"a,b\"")
        XCTAssertEqual(Exporter.csvQuote("say \"hi\""), "\"say \"\"hi\"\"\"")
    }

    func testCSVHasOneRowPerVariantWithHeader() {
        let run = CollationRunner.run(CLIOptions(explicitFiles: ["A", "B"]),
                                      witnesses: [Witness(id: "A", text: "the cat sat"),
                                                  Witness(id: "B", text: "the dog sat")])
        let lines = Exporter.csv(run).split(separator: "\n")
        XCTAssertTrue(lines[0].hasPrefix("pair_base,pair_compared,type"))
        XCTAssertEqual(lines.count, 2, "one header + one variant (cat→dog)")
        XCTAssertTrue(lines[1].contains("substitution"))
    }

    /// The load-bearing tie to the corpus: the CLI's JSON export is byte-identical to the committed golden for
    /// the same witnesses + options — because both go through `CollationJSON.outputString`.
    func testJSONExportEqualsConformanceGolden() throws {
        // Use conformance case 02-insertion (has a pure insertion → exercises B6c through the CLI too).
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/conformance")
        let caseDir = root.appendingPathComponent("cases/02-insertion")
        let metaData = try Data(contentsOf: caseDir.appendingPathComponent("meta.json"))
        struct Meta: Decodable { let witnessOrder: [String] }
        let order = try JSONDecoder().decode(Meta.self, from: metaData).witnessOrder
        let paths = order.map { caseDir.appendingPathComponent("\($0).txt").path }

        var o = CLIOptions(explicitFiles: paths)
        _ = try? CLIParser.validate(o)
        o.explicitFiles = paths
        let ws = try WitnessLoader.load(o)
        let run = CollationRunner.run(o, witnesses: ws)
        let produced = Exporter.json(run) + "\n"

        let golden = try String(contentsOf: root.appendingPathComponent("golden/02-insertion.json"), encoding: .utf8)
        XCTAssertEqual(produced, golden, "CLI JSON export must equal the conformance golden (same code path)")
    }

    // MARK: end-to-end dispatch

    func testRunWritesAllExpectedFiles() throws {
        let dir = try tempDir(["A.txt": "the cat sat", "B.txt": "the cat quietly sat"])
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let out = dir + "/out"
        let sink = CapturingSink()
        let code = CollateCLI.main(["run", "--dir", dir, "--all", "--format", "csv", "--out", out], sink: sink)
        XCTAssertEqual(code, 0)
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: out))
        // CSV format → variants.csv; plus the always-written interchange + manifest.
        XCTAssertTrue(files.isSuperset(of: ["variants.csv", "collation.json", "manifest.txt"]), "got \(files)")
    }

    func testHelpAndVersionSucceed() {
        let sink = CapturingSink()
        XCTAssertEqual(CollateCLI.main(["--help"], sink: sink), 0)
        XCTAssertTrue(sink.outLines.joined().contains("collate run"))
        let v = CapturingSink()
        XCTAssertEqual(CollateCLI.main(["--version"], sink: v), 0)
    }

    func testUnknownCommandIsUsageError() {
        let sink = CapturingSink()
        XCTAssertEqual(CollateCLI.main(["frobnicate"], sink: sink), 1)
    }

    /// Determinism: the same run exports byte-identical files twice (guards the sorted/stable output claim).
    func testExportIsDeterministic() {
        let run = CollationRunner.run(CLIOptions(explicitFiles: ["A", "B"]),
                                      witnesses: [Witness(id: "A", text: "a b c"),
                                                  Witness(id: "B", text: "a b inserted c")])
        XCTAssertEqual(Exporter.files(for: run), Exporter.files(for: run))
    }
}
