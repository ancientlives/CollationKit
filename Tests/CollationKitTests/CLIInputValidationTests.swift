import XCTest
@testable import CollationKit
@testable import CollateCLI

// MARK: - CLI and menu input handling (release 1 review, blockers B13 and B14)
//
// B13: witness ids (file names without extension) were not checked for uniqueness, so `e1818/text.txt` and
// `e1831/text.txt` both became `text` and their readings merged. B14: the menu ran the collation when you answered
// "no" (or stdin ended) at the confirm prompt; a mistyped base was caught only after the confirm, and the menu exited;
// "edit options" forgot earlier answers; an unwritable `--out` was found only after the whole collation; and the
// documented `collate --no-input run …` and `collate run --help` failed.

final class CLIInputValidationTests: XCTestCase {

    final class Sink: OutputSink {
        var outLines: [String] = []; var errLines: [String] = []
        func out(_ s: String) { outLines.append(s) }
        func err(_ s: String) { errLines.append(s) }
    }

    private var cleanup: [String] = []
    override func tearDown() { for p in cleanup { try? FileManager.default.removeItem(atPath: p) } }

    private func tempDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory() + "cli-\(UUID().uuidString)"
        cleanup.append(dir)
        for (name, text) in files {
            let path = (dir as NSString).appendingPathComponent(name)
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                    withIntermediateDirectories: true)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func run(_ args: [String]) -> (code: Int32, sink: Sink) {
        let sink = Sink()
        return (CollateCLI.main(args, sink: sink), sink)
    }

    // MARK: B13 — duplicate witness ids

    func testTwoFilesWithTheSameNameAreRejected() throws {
        let root = try tempDir(["e1818/text.txt": "the red door", "e1831/text.txt": "the blue door"])
        let (code, sink) = run(["run", "\(root)/e1818/text.txt", "\(root)/e1831/text.txt"])
        XCTAssertEqual(code, Int32(CLIError.Kind.witnesses.rawValue))
        XCTAssertTrue(sink.errLines.joined().contains("two witnesses have the id 'text'"), sink.errLines.joined())
    }

    func testTheSameFileTwiceAndARepeatedOrderAreRejected() throws {
        let root = try tempDir(["A.txt": "the red door", "B.txt": "the blue door"])
        XCTAssertNotEqual(run(["run", "\(root)/A.txt", "\(root)/A.txt"]).code, 0)
        XCTAssertNotEqual(run(["run", "--dir", root, "\(root)/A.txt"]).code, 0, "a directory plus one of its files")
        let (code, sink) = run(["run", "--dir", root, "--order", "A,A,B"])
        XCTAssertNotEqual(code, 0)
        XCTAssertTrue(sink.errLines.joined().contains("more than once"))
    }

    // MARK: B14 — command line

    func testNoInputBeforeASubcommandWorks() throws {
        let root = try tempDir(["A.txt": "the red door", "B.txt": "the blue door"])
        XCTAssertEqual(run(["--no-input", "run", "\(root)/A.txt", "\(root)/B.txt"]).code, 0)
    }

    func testSubcommandHelpPrintsUsage() {
        for args in [["run", "--help"], ["list", "-h"]] {
            let (code, sink) = run(args)
            XCTAssertEqual(code, 0, "\(args)")
            XCTAssertTrue(sink.outLines.joined().contains("USAGE"), "\(args)")
        }
    }

    func testAnUnwritableOutputFolderFailsBeforeCollating() throws {
        let root = try tempDir(["A.txt": "the red door", "B.txt": "the blue door", "out/.keep": ""])
        let out = "\(root)/out"
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: out)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: out) }
        let (code, sink) = run(["run", "\(root)/A.txt", "\(root)/B.txt", "--out", out])
        XCTAssertEqual(code, Int32(CLIError.Kind.io.rawValue))
        XCTAssertFalse(sink.errLines.contains { $0.contains("collating pair") }, "no collation work was done first")
    }

    // MARK: B14 — interactive menu

    private func witnessDir() throws -> String {
        try tempDir(["MS.txt": "the cat sat", "TS.txt": "the cat sat still", "PR.txt": "the dog sat"])
    }

    func testAnsweringNoAtTheConfirmDoesNotRun() throws {
        let dir = try witnessDir()
        // Browse (use), six option defaults, export = no, then "no" → edit; on the second pass, quit at the browser.
        let io = ScriptedConsoleIO(["u", "", "", "", "", "", "", "1", "no", "q"])
        XCTAssertEqual(Menu.run(io: io, initial: CLIOptions(directory: dir)), .quit)
    }

    func testEndOfInputAtTheConfirmQuits() throws {
        let dir = try witnessDir()
        let io = ScriptedConsoleIO(["u", "", "", "", "", "", "", "1"])
        XCTAssertEqual(Menu.run(io: io, initial: CLIOptions(directory: dir)), .quit)
    }

    func testAnUnrecognisedConfirmAnswerAsksAgain() throws {
        let dir = try witnessDir()
        let io = ScriptedConsoleIO(["u", "", "", "", "", "", "", "1", "maybe", "y"])
        guard case .run = Menu.run(io: io, initial: CLIOptions(directory: dir)) else { return XCTFail("expected .run") }
        XCTAssertTrue(io.written.contains { $0.contains("Please answer y") })
    }

    func testAMistypedBaseIsAskedAgain() throws {
        let dir = try witnessDir()
        let io = ScriptedConsoleIO(["u", "", "BB", "TS", "", "", "", "", "1", "y"])
        guard case .run(let o) = Menu.run(io: io, initial: CLIOptions(directory: dir)) else { return XCTFail("expected .run") }
        XCTAssertEqual(o.base, "TS")
        XCTAssertTrue(io.written.contains { $0.contains("'BB' is not one of") })
    }

    func testEditingKeepsThePreviousAnswers() throws {
        let dir = try witnessDir()
        // First pass: witnesses 1,3; pagination 2 with 50 lines/page; export no; then "n" to edit.
        // Second pass: accept every default; the earlier answers must be offered and kept.
        let io = ScriptedConsoleIO(["u", "1,3", "", "", "", "2", "50", "", "1", "n",
                                    "u", "", "", "", "", "", "", "", "1", "y"])
        guard case .run(let o) = Menu.run(io: io, initial: CLIOptions(directory: dir)) else { return XCTFail("expected .run") }
        XCTAssertEqual(o.order?.count, 2, "the witness subset is kept")
        XCTAssertEqual(o.pagination, .linesPerPage(50), "the pagination is kept")
    }
}
