import XCTest
@testable import CollateCLI

// MARK: - Directory browser tests (BACKLOG B9 phase 3)
//
// `DirectoryBrowser.choose` lets the menu user navigate to a folder visually — a unified list of subfolders
// (numbered, `<n>` opens) plus the witness files present (shown so you can see what you'd collate), `..` up,
// `u`/Enter to USE the current folder, a typed path shortcut, `q` cancel. Driven here with a `ScriptedConsoleIO`
// over a real temp tree — no terminal.

final class DirectoryBrowserTests: XCTestCase {

    /// Build a temp tree and return its root. `subdirs` created under root; `files` written at root.
    private func tree(_ subdirs: [String], files: [String] = []) throws -> String {
        let root = NSTemporaryDirectory() + "browse-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
        for d in subdirs { try fm.createDirectory(atPath: (root as NSString).appendingPathComponent(d),
                                                  withIntermediateDirectories: true) }
        for f in files { try "some text here".write(toFile: (root as NSString).appendingPathComponent(f),
                                                    atomically: true, encoding: .utf8) }
        return root
    }

    /// Two witness files here → `u` (use) selects the current folder.
    func testUseSelectsCurrentFolderWhenEnoughWitnesses() throws {
        let root = try tree([], files: ["A.txt", "B.txt"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let io = ScriptedConsoleIO(["u"])
        XCTAssertEqual(DirectoryBrowser.choose(io: io, start: root, title: "Dir", requireExisting: true), root)
    }

    /// Enter (empty) is a synonym for `u`.
    func testEnterIsSynonymForUse() throws {
        let root = try tree([], files: ["A.md", "B.md"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let io = ScriptedConsoleIO([""])
        XCTAssertEqual(DirectoryBrowser.choose(io: io, start: root, title: "Dir", requireExisting: true), root)
    }

    /// A witness folder with <2 files can't be USED — it warns and keeps browsing (here: up, then use root).
    func testWitnessFolderNeedsTwoFiles() throws {
        let root = try tree(["sub"], files: ["A.txt", "B.txt"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let sub = (root as NSString).appendingPathComponent("sub")   // sub has 0 witness files
        let io = ScriptedConsoleIO(["u", "..", "u"])                 // try to use sub (refused) → up → use root
        XCTAssertEqual(DirectoryBrowser.choose(io: io, start: sub, title: "Dir", requireExisting: true), root)
        XCTAssertTrue(io.transcript.contains("needs at least 2"), "explains why an empty folder can't be used")
    }

    /// Opening a numbered subfolder, then using it.
    func testOpenByNumberThenUse() throws {
        let root = try tree(["alpha", "beta"])       // sorted → 1) alpha, 2) beta
        defer { try? FileManager.default.removeItem(atPath: root) }
        // beta has no files; add two so it can be used.
        let beta = (root as NSString).appendingPathComponent("beta")
        try "x".write(toFile: (beta as NSString).appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try "y".write(toFile: (beta as NSString).appendingPathComponent("B.txt"), atomically: true, encoding: .utf8)
        let io = ScriptedConsoleIO(["2", "u"])       // open beta, then use it
        XCTAssertEqual(DirectoryBrowser.choose(io: io, start: root, title: "Dir", requireExisting: true), beta)
    }

    /// `..` and `../` both go up to the parent (the Unix relative-parent form).
    func testUpGoesToParent() throws {
        let root = try tree(["child"], files: ["A.txt", "B.txt"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let start = (root as NSString).appendingPathComponent("child")
        for up in ["..", "../"] {                     // both spellings mean "up a level"
            let io = ScriptedConsoleIO([up, "u"])     // up to root (which has the 2 files), then use
            XCTAssertEqual(DirectoryBrowser.choose(io: io, start: start, title: "Dir", requireExisting: true), root,
                           "`\(up)` should go up one level")
        }
    }

    /// Regression: a RELATIVE start (e.g. ".") must resolve to the absolute cwd so `../` goes to the cwd's
    /// PARENT, not the filesystem root. Bug: `current = "."` made `deletingLastPathComponent` → "" → "/".
    func testRelativeStartResolvesSoUpIsNotRoot() throws {
        let root = try tree(["work"], files: [])                 // a real tree with a subdir to cd into
        let work = (root as NSString).appendingPathComponent("work")
        try "x".write(toFile: (work as NSString).appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try "y".write(toFile: (work as NSString).appendingPathComponent("B.txt"), atomically: true, encoding: .utf8)
        let fm = FileManager.default
        let savedCwd = fm.currentDirectoryPath
        defer { fm.changeCurrentDirectoryPath(savedCwd); try? fm.removeItem(atPath: root) }
        fm.changeCurrentDirectoryPath(work)                      // cwd = …/work

        // Start relative ("."): `../` must land in `root` (work's parent), NOT "/".
        let io = ScriptedConsoleIO(["../", "q"])
        _ = DirectoryBrowser.choose(io: io, start: ".", title: "Dir", requireExisting: true)
        let rootReal = (root as NSString).standardizingPath      // /var → /private/var etc.
        XCTAssertTrue(io.transcript.contains(rootReal),
                      "`../` from cwd should show the cwd's parent (\(rootReal)), not root")
        XCTAssertFalse(io.transcript.contains("Dir:  /\n") || io.transcript.contains("Dir:  / "),
                       "`../` from cwd must not jump to the filesystem root")
    }

    /// A typed absolute path to an existing directory navigates there; `u` then uses it.
    func testTypedPathNavigates() throws {
        let root = try tree(["deep/nested"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let target = (root as NSString).appendingPathComponent("deep/nested")
        try "x".write(toFile: (target as NSString).appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try "y".write(toFile: (target as NSString).appendingPathComponent("B.txt"), atomically: true, encoding: .utf8)
        let io = ScriptedConsoleIO([target, "u"])
        XCTAssertEqual(DirectoryBrowser.choose(io: io, start: root, title: "Dir", requireExisting: true), target)
    }

    /// `q` cancels (nil); EOF (empty script) also cancels.
    func testCancel() throws {
        let root = try tree([], files: ["A.txt", "B.txt"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        XCTAssertNil(DirectoryBrowser.choose(io: ScriptedConsoleIO(["q"]), start: root, title: "Dir", requireExisting: true))
        XCTAssertNil(DirectoryBrowser.choose(io: ScriptedConsoleIO([]), start: root, title: "Dir", requireExisting: true))
    }

    /// Output purpose: requireExisting=false accepts a not-yet-created typed path immediately; requireExisting
    /// rejects a missing path and keeps browsing.
    func testOutputAcceptsToBeCreatedPath() throws {
        let root = try tree([])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let newPath = (root as NSString).appendingPathComponent("to-be-made")

        let io1 = ScriptedConsoleIO([newPath])   // output: accept immediately
        XCTAssertEqual(DirectoryBrowser.choose(io: io1, start: root, title: "Out",
                                               requireExisting: false, purpose: .output), newPath)

        let io2 = ScriptedConsoleIO([newPath, "u"])   // requireExisting: reject (warn), then use root
        XCTAssertEqual(DirectoryBrowser.choose(io: io2, start: root, title: "Out",
                                               requireExisting: true, purpose: .output), root)
        XCTAssertTrue(io2.transcript.contains("no such directory"))
    }

    /// The listing shows subfolders and the witness files present, and skips dotfiles + non-witness files.
    func testListingShowsFoldersAndWitnessFiles() throws {
        let root = try tree(["visible", ".hidden"], files: ["A.txt", "B.md", "notes.pdf"])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let io = ScriptedConsoleIO(["q"])
        _ = DirectoryBrowser.choose(io: io, start: root, title: "Dir", requireExisting: true)
        XCTAssertTrue(io.transcript.contains("visible/"), "lists the visible subfolder")
        XCTAssertFalse(io.transcript.contains(".hidden"), "skips dotfiles")
        XCTAssertTrue(io.transcript.contains("A.txt"), "shows witness files present")
        XCTAssertTrue(io.transcript.contains("B.md"), "shows .md witnesses too")
        XCTAssertFalse(io.transcript.contains("notes.pdf"), "skips non-witness files")
    }
}
