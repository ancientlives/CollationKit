import XCTest
@testable import CollateCLI
@testable import CollationKit

// MARK: - Interactive menu tests (BACKLOG B9 phase 3, CLI_PLAN §8)
//
// The whole reason `Menu` is written against the `ConsoleIO` protocol: it can be driven with a
// `ScriptedConsoleIO` (a queued answer list) through every path — accept defaults, subset + base + order,
// diplomatic, export-vs-console, quit, and the <2-witnesses branch — with NO terminal. These assert the
// assembled `CLIOptions` and the transcript, without collating anything (the run itself is exercised by
// CollateCLITests). Answers are dequeued in prompt order.

final class MenuTests: XCTestCase {

    private func w(_ id: String, _ text: String) -> Witness { Witness(id: id, text: text) }

    /// A temp directory of witness files (returns the path; caller cleans up).
    private func tempDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory() + "menu-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(toFile: (dir as NSString).appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func threeWitnessDir() throws -> String {
        try tempDir(["MS.txt": "the cat sat", "TS.txt": "the cat sat still", "PR.txt": "the dog sat"])
    }

    // MARK: parseSelection (the "which witnesses" grammar)

    func testParseSelectionAllAndIndices() {
        let sigla = ["MS", "TS", "PR", "GB1"]
        XCTAssertEqual(Menu.parseSelection("all", sigla: sigla), sigla)
        XCTAssertEqual(Menu.parseSelection("", sigla: sigla), sigla)
        XCTAssertEqual(Menu.parseSelection("1,3", sigla: sigla), ["MS", "PR"])
        XCTAssertEqual(Menu.parseSelection("3,1,3", sigla: sigla), ["PR", "MS"], "dedup, order preserved")
        XCTAssertEqual(Menu.parseSelection("9", sigla: sigla), sigla, "no valid index → fall back to all")
    }

    // MARK: full flows

    /// Accept every default, confirm with `y` → run all witnesses, base = first, to console.
    /// The witness-directory step is a browser: typing the path navigates into it, then an empty line SELECTS
    /// the current folder. The export step is a Yes/No choice (1 = console only).
    func testAcceptAllDefaultsProducesRunOptions() throws {
        let dir = try threeWitnessDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // Order: dir(type→enter), which, base, order, mode, pagination, format, export=1(no), confirm.
        let io = ScriptedConsoleIO([dir, "", "", "", "", "", "", "", "1", "y"])
        guard case .run(let o) = Menu.run(io: io) else { return XCTFail("expected .run") }
        XCTAssertEqual(o.directory, dir)
        XCTAssertNil(o.order, "‘all’ in original order → no explicit order")
        XCTAssertNil(o.base, "base = first → no explicit base")
        XCTAssertEqual(o.mode, .substantive)
        XCTAssertEqual(o.format, .text)
        XCTAssertNil(o.outDir, "export ‘No’ → console only")
    }

    /// Choose a subset + base + diplomatic + csv + an export folder.
    func testSubsetBaseDiplomaticExport() throws {
        let dir = try threeWitnessDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // Discovery is sorted: [MS, PR, TS]. dir(type→enter); which = "1,3" → MS,TS; base = TS; order accept;
        // mode 2 (diplomatic); pagination 1; format 3 (csv); export=2(yes) → browse types a new folder path
        // (accepted as to-be-created); confirm y.
        let io = ScriptedConsoleIO([dir, "", "1,3", "TS", "", "2", "1", "3", "2", "/tmp/out-x", "y"])
        guard case .run(let o) = Menu.run(io: io) else { return XCTFail("expected .run") }
        XCTAssertEqual(o.order, ["MS", "TS"], "subset selection (sorted discovery order)")
        XCTAssertEqual(o.base, "TS")
        XCTAssertEqual(o.mode, .diplomatic)
        XCTAssertEqual(o.format, .csv)
        XCTAssertEqual(o.outDir, "/tmp/out-x")
    }

    /// `q` at the first prompt quits without running.
    func testQuitAtFirstPrompt() throws {
        let io = ScriptedConsoleIO(["q"])
        XCTAssertEqual(Menu.run(io: io), .quit)
    }

    /// EOF (empty script) also quits, so a piped/empty stdin can't hang.
    func testEOFQuits() {
        let io = ScriptedConsoleIO([])
        XCTAssertEqual(Menu.run(io: io), .quit)
    }

    /// A folder with <2 witnesses can't be USED — the browser explains and keeps browsing (no bounce out to a
    /// re-ask); typing a good directory's path then navigates there and succeeds.
    func testFewerThanTwoWitnessesReasksThenSucceeds() throws {
        let small = try tempDir(["only.txt": "hi"])
        let good = try threeWitnessDir()
        defer { try? FileManager.default.removeItem(atPath: small); try? FileManager.default.removeItem(atPath: good) }
        // Browser starts at `small` (1 file): `u` is refused (warn) → type `good`'s path (navigate in) → `u`
        // uses it; then accept the six option defaults, export=1(no), confirm. (This script was one answer short;
        // it passed only because end of input at the confirm prompt used to RUN — the B14 bug.)
        let io = ScriptedConsoleIO(["u", good, "u", "", "", "", "", "", "", "1", "y"])
        guard case .run(let o) = Menu.run(io: io, initial: CLIOptions(directory: small)) else {
            return XCTFail("expected .run after navigating past the small folder")
        }
        XCTAssertEqual(o.directory, good)
        XCTAssertTrue(io.transcript.contains("needs at least 2"), "the browser explains why a <2 folder can't be used")
    }

    /// Declining the confirm with `n` edits options (loops), then `q` quits.
    func testDeclineConfirmLoopsThenQuit() throws {
        let dir = try threeWitnessDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // First pass: dir(type→enter) + defaults + export=1, then `n` (edit) → loop restarts; on the restart,
        // `q` at the dir browser quits.
        let io = ScriptedConsoleIO([dir, "", "", "", "", "", "", "", "1", "n", "q"])
        XCTAssertEqual(Menu.run(io: io), .quit)
    }

    // MARK: dispatch integration — the bare `collate` invocation launches the menu

    func testBareInvocationLaunchesMenuAndRuns() throws {
        let dir = try threeWitnessDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        final class Sink: OutputSink { var o: [String] = []; var e: [String] = []
            func out(_ s: String) { o.append(s) }; func err(_ s: String) { e.append(s) } }
        let sink = Sink()
        let io = ScriptedConsoleIO([dir, "", "", "", "", "", "", "", "1", "y"])
        // No subcommand + a console → interactive menu, then collate to console.
        let code = CollateCLI.main([], sink: sink, console: io)
        XCTAssertEqual(code, 0)
        XCTAssertTrue(sink.o.joined().contains("LOCATED VARIANT REPORT"), "menu should have run a collation")
    }

    /// `--no-input` with no subcommand is a usage error (CI must use an explicit `run`).
    func testNoInputWithoutCommandIsUsageError() {
        final class Sink: OutputSink { var o: [String] = []; var e: [String] = []
            func out(_ s: String) { o.append(s) }; func err(_ s: String) { e.append(s) } }
        let sink = Sink()
        let code = CollateCLI.main(["--no-input"], sink: sink, console: ScriptedConsoleIO([]))
        XCTAssertEqual(code, 1)
    }

    /// `--dir <path>` (no subcommand) pre-seeds the directory prompt.
    func testDirFlagPreseedsMenuDirectory() throws {
        let dir = try threeWitnessDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        // The browser starts at the pre-seeded directory, so an empty line SELECTS it immediately; then
        // defaults, export=1(no), confirm.
        let io = ScriptedConsoleIO(["", "", "", "", "", "", "", "1", "y"])
        let initial = CLIOptions(directory: dir)
        guard case .run(let o) = Menu.run(io: io, initial: initial) else { return XCTFail("expected .run") }
        XCTAssertEqual(o.directory, dir)
    }
}
