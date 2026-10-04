import CollationKit
import Foundation

// MARK: - The CLI core entry point (BACKLOG B9, CLI_PLAN §2, §3)
//
// `CollateCLI.main` is the testable heart of the `collate` tool: it takes argv (minus the program name) and an
// abstract output sink, dispatches the subcommand, and returns an exit code. It performs NO process control
// (no `exit`, no direct `print`) so it can be unit-tested by feeding args and capturing output — the thin
// `collate` executable wires real stdout/stderr + `exit(code)` around it. (The interactive menu is a later
// phase; Stage A is the scriptable `run`/`list` + `--help`.)

/// Where the CLI writes normal and error output. The shell binds this to stdout/stderr; tests capture it.
public protocol OutputSink {
    func out(_ s: String)
    func err(_ s: String)
}

public enum CollateCLI {

    /// Keep in step with `CITATION.cff` (`VersionConsistencyTests` checks it) and the CHANGELOG.
    public static let version = "0.3.0"

    /// Dispatch on argv (without the program name). Returns a POSIX exit code (0 ok; 1 usage; 2 witnesses;
    /// 3 IO). Never throws — every error is mapped to a message + code.
    public static func main(_ args: [String], sink: OutputSink) -> Int32 {
        main(args, sink: sink, console: nil)
    }

    /// As `main`, but with an optional `ConsoleIO` for the interactive menu (BACKLOG B9 phase 3). The `collate`
    /// shell passes a real `TerminalConsoleIO`; tests pass a `ScriptedConsoleIO`. With no subcommand (or just
    /// `--dir <path>`), and a console available, this launches the menu; `--no-input` forbids that (for CI).
    public static func main(_ args: [String], sink: OutputSink, console: ConsoleIO?) -> Int32 {
        var args = args
        // `--no-input` is a global flag (forbid the menu). Before a subcommand it used to be read as the command
        // itself, so the documented `collate --no-input run …` failed (release 1 review, B14).
        if args.count > 1, args[0] == "--no-input", ["run", "list"].contains(args[1]) { args.removeFirst() }
        // A no-subcommand invocation (nothing, or only `--dir <path>`) means "interactive menu".
        if isInteractiveInvocation(args) {
            if args.contains("--no-input") {
                sink.err("error: --no-input given but no command; use `collate run …`\n\n\(usage)")
                return CLIError.Kind.usage.rawValue.int32
            }
            guard let console else { sink.err(usage); return CLIError.Kind.usage.rawValue.int32 }
            return dispatch { try menuCommand(args, sink: sink, console: console) }(sink)
        }
        let first = args[0]
        if ["run", "list"].contains(first), args.contains("--help") || args.contains("-h") {
            sink.out(usage); return 0                     // `collate run --help` (documented; used to error)
        }
        switch first {
        case "--help", "-h":     sink.out(usage); return 0
        case "--version":        sink.out("collate \(version)"); return 0
        case "run":              return dispatch { try runCommand(Array(args.dropFirst()), sink: sink) }(sink)
        case "list":             return dispatch { try listCommand(Array(args.dropFirst()), sink: sink) }(sink)
        default:
            sink.err("unknown command '\(first)'\n\n\(usage)")
            return CLIError.Kind.usage.rawValue.int32
        }
    }

    /// True when there is no subcommand — argv is empty, or contains only the `--dir <path>` pre-seed (and
    /// optionally `--no-input`). Anything else (a subcommand, `--help`, files) is handled non-interactively.
    static func isInteractiveInvocation(_ args: [String]) -> Bool {
        if args.isEmpty { return true }
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--dir":       i += 2                     // skip the path value
            case "--no-input":  i += 1
            default:            return false               // any real token → not the bare interactive form
            }
        }
        return true
    }

    /// Run a throwing command, mapping a thrown `CLIError` to its message + exit code (0 on success).
    private static func dispatch(_ body: @escaping () throws -> Void) -> (OutputSink) -> Int32 {
        { sink in
            do { try body(); return 0 }
            catch let e as CLIError { sink.err("error: \(e.message)"); return e.kind.rawValue.int32 }
            catch { sink.err("error: \(error.localizedDescription)"); return CLIError.Kind.io.rawValue.int32 }
        }
    }

    // MARK: run

    static func runCommand(_ args: [String], sink: OutputSink) throws {
        let opts = try CLIParser.parseRun(args)
        try CLIParser.validate(opts)
        try execute(opts, sink: sink)
    }

    // MARK: menu (interactive)

    static func menuCommand(_ args: [String], sink: OutputSink, console: ConsoleIO) throws {
        // Pre-seed the directory prompt from `--dir <path>` if present.
        var initial = CLIOptions()
        if let idx = args.firstIndex(of: "--dir"), idx + 1 < args.count { initial.directory = args[idx + 1] }
        switch Menu.run(io: console, initial: initial) {
        case .quit:
            console.write("  (quit — nothing collated)")
        case .run(let opts):
            console.write("")
            console.write("  … collating …")
            try execute(opts, sink: sink)   // SAME path as `run` — one config, two front doors
        }
    }

    /// Run a validated `CLIOptions`: load witnesses, collate, and either export or print to the console. Shared
    /// by the `run` subcommand and the interactive menu so both drive the engine identically.
    ///
    /// Progress goes to the ERROR channel (stderr), so a long collation is never silent — the user sees each
    /// stage as it starts — while stdout stays clean for piped `--format json/csv/html` output. The run ends
    /// with an explicit "✓ collation finished" line (also stderr) with counts and elapsed time.
    static func execute(_ opts: CLIOptions, sink: OutputSink) throws {
        let witnesses = try WitnessLoader.load(opts)
        let lexicon = try loadLexicon(opts)
        // Check the output folder BEFORE collating: an unwritable folder used to be found only after the whole
        // run (minutes on a full novel in a debug build) had been thrown away (release 1 review, B14).
        if let dir = opts.outDir { try Exporter.preflight(directory: dir) }
        let started = Date()
        sink.err("→ \(witnesses.count) witnesses loaded (base \(witnesses.first?.id ?? "?")): "
                 + witnesses.map { "\($0.id) (\($0.text.count) chars)" }.joined(separator: ", "))
        #if DEBUG
        // `swift run collate` builds DEBUG, which is many times slower than release — on full-novel input the
        // difference is SECONDS vs. MINUTES, and a stage grinding for minutes reads as a hang (measured: the
        // full 2-witness *20,000 Leagues* pair finishes in ~5s release, but does NOT finish in 2 min debug).
        // The graph-build and pairwise-collation stages now report per-witness sub-steps, so it is visibly
        // progressing rather than frozen — but the real fix on a large input is a release build. Say so up front.
        if witnesses.reduce(0, { $0 + $1.text.count }) > 200_000 {
            sink.err("⚠ DEBUG build on a large input — stages take MINUTES (a frozen-looking stage is almost "
                     + "certainly this). Use a release build: swift run -c release collate … / .build/release/collate …")
        }
        #endif

        // The interactive HTML viewer needs base-anchored pairs; compute them whenever the viewer will be
        // produced (any export, or an explicit html format).
        let wantsViewer = opts.outDir != nil || opts.format == .html
        let run = CollationRunner.run(opts, witnesses: witnesses, lexicon: lexicon,
                                      includeViewerPairs: wantsViewer,
                                      progress: { sink.err("→ \($0)") })

        sink.err("→ rendering (\(opts.format.rawValue)) …")
        var openHint: String? = nil
        if let dir = opts.outDir {
            let written = try Exporter.write(run, toDirectory: dir,
                                             timestamp: ISO8601DateFormatter().string(from: Date()),
                                             progress: { sink.err("→ \($0)") })
            sink.out("wrote:")
            for p in written { sink.out("   \(p)") }
            openHint = written.first { $0.hasSuffix("collation.html") }
        } else {
            // No `--out`: stream the picked format straight to stdout. The text view is capped for the console
            // (a full-novel report is millions of characters — that is what `--out` is for).
            switch opts.format {
            case .text: sink.out(Exporter.consolePreview(run))
            case .json: sink.out(Exporter.json(run))
            case .csv:  sink.out(Exporter.csv(run))
            case .html: sink.out(HTMLExport.html(run))
            }
        }

        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        sink.err("✓ collation finished — \(run.witnessOrder.count) witnesses, "
                 + "\(run.totalPairVariants) variant(s) across \(run.pairs.count) pair(s), "
                 + "\(run.graph.variantNodes.count) variant node(s) in the graph — in \(elapsed)s")
        if let path = openHint {
            sink.err("  open \(path) to explore the collation interactively")
        }
    }

    /// Load and parse the B10 translation lexicon named by `--lexicon`, if any. A missing/unreadable file is
    /// an IO error; a file that parses to an EMPTY lexicon is a usage error (the flag would silently do
    /// nothing — likely a malformed file, so fail loudly).
    static func loadLexicon(_ opts: CLIOptions) throws -> TranslationLexicon? {
        guard let rawPath = opts.lexiconPath else { return nil }
        let path = Paths.expand(rawPath)
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw CLIError(.io, "cannot read --lexicon file '\(path)'")
        }
        let lexicon = TranslationLexicon.parse(text)
        guard !lexicon.isEmpty else {
            throw CLIError(.usage,
                "--lexicon '\(path)' contains no equivalence groups (one group per line, forms separated by commas)")
        }
        return lexicon
    }

    // MARK: list

    static func listCommand(_ args: [String], sink: OutputSink) throws {
        // `list --dir <path>`: show the witness files discovered (a convenient extra, CLI_PLAN §3).
        guard let idx = args.firstIndex(of: "--dir"), idx + 1 < args.count else {
            throw CLIError(.usage, "list requires --dir <path>")
        }
        let discovered = try WitnessLoader.discover(inDirectory: args[idx + 1])
        if discovered.isEmpty { sink.out("(no witness files found — looked for .txt/.md)"); return }
        sink.out("Found \(discovered.count) witness file(s):")
        for d in discovered { sink.out("  \(d.siglum)\t\(d.path)") }
    }

    // MARK: help

    static let usage = """
    collate — a harness for the CollationKit engine (BACKLOG B9, Stage A)

    USAGE:
      collate                             INTERACTIVE MENU — browse to a witness folder + an output folder,
                                          pick options, run. Start here if you're not scripting.
      collate --dir <path>                the menu, with the directory browser starting at <path>
      collate run [witness files…]        scriptable: collate the given files (first = base); NO menu
      collate run --dir <path> --all      scriptable: collate every .txt/.md witness in a directory
      collate list --dir <path>           list the witness files discovered in a directory
      collate --help | --version

      (`run` needs witness files or --dir …/--all and errors if given none — it is the no-menu path for
       CI/pipes. Plain `collate` with no subcommand is the interactive menu. --no-input also forbids the menu.)

    RUN OPTIONS:
      --dir <path>              discover witnesses in a directory
      --all                     use all discovered witnesses
      --base <siglum>           choose the base (copy-text); default: first in order
      --order <a,b,c>           explicit witness order (and subset)
      --substantive             fold accidentals (default)
      --diplomatic              exact comparison: case, accents and punctuation differences are all variants
      --accidentals             report spelling/case accidentals
      --record-punctuation      report punctuation accidentals
      --lines-per-page <N>      (experimental) cite against a uniform printed page of N text lines
      --through-numbered        (experimental) continuous line numbering (no per-page reset)
      --format <f>              output encoding: text (default), json, csv, or html — the interactive
                                collation viewer (perspective tabs, alignment highlights, variant panel)
      --strategy <s>            N-witness merge strategy: base-anchored (default; apparatus keyed to the
                                copy-text) or peer-msa (peer alignment — best for base-free material,
                                competing translations, and cross-language sets)
      --scoring prose|verse     alignment scoring preset (default: prose; verse biases toward whole-line insert/delete)
      --lexicon <path>          (experimental) translation lexicon for cross-language collation (one
                                equivalence group per line, forms separated by commas: "année, year");
                                pairs best with peer-msa
      --out <dir>               export to a directory (collation.json + manifest always written)

    A witness's id is its filename stem (MS.txt → MS), and ids must be unique. Input conventions (page breaks,
    no_collate regions, the lexicon format) are in docs/guides/INPUT_FORMAT.md. With --out, a run also writes the machine-readable
    collation.json interchange and a self-describing manifest, so results are reproducible downstream.

    FULL TEXTS: build once with `-c release` and run the optimised binary — a debug build is minutes slower and
    looks frozen (`swift build -c release` then `.build/release/collate run …`). See docs/development/BENCHMARKS.md.
    """
}

private extension Int {
    var int32: Int32 { Int32(self) }
}
