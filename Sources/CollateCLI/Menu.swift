import CollationKit
import Foundation

// MARK: - The interactive menu (BACKLOG B9 phase 3, CLI_PLAN §5)
//
// A prompt-driven flow that builds a `CLIOptions` by asking the user, step by step, for a witness directory,
// which witnesses, base/order, comparison mode, pagination, format, and an optional export folder — then a
// confirm. It is pure logic over the `ConsoleIO` seam (no real terminal), so `MenuTests` drives it with a
// `ScriptedConsoleIO`. On confirm it returns the assembled `CLIOptions`; the caller (`CollateCLI`) runs it via
// the SAME `CollationRunner`/`Exporter` path as the non-interactive `run` command — one config, two front doors.
//
// Conventions (CLI_PLAN §5): every prompt shows the current default in `[brackets]`; empty input accepts it;
// `q` quits. EOF (nil input) is treated as quit, so a piped/empty stdin can never hang. Back-navigation (`b`)
// and the section picker are noted as Stage-B refinements; Stage A covers the full option set forward.

public enum Menu {

    /// The outcome of an interactive session: run these options, or the user quit.
    public enum Outcome: Equatable { case run(CLIOptions); case quit }

    /// Drive the interactive flow over `io`, starting from `initial` (e.g. a `--dir` passed on the command
    /// line pre-seeds the directory prompt). Returns the options to run, or `.quit`.
    public static func run(io: ConsoleIO, initial: CLIOptions = CLIOptions()) -> Outcome {
        io.write("")
        io.write("  CollationKit · interactive collation")
        io.write("  ════════════════════════════════════")

        // Loop the whole flow so "edit options" at the end restarts from the top with the last answers as
        // defaults. `current` carries defaults forward across edits.
        var current = initial
        while true {
            guard let assembled = collect(io: io, defaults: current) else { return .quit }
            current = assembled

            // Summary + confirm.
            io.write("")
            io.write("  ── Summary " + String(repeating: "─", count: 52))
            io.write("   " + summary(assembled))
            switch ask(io, "  Run? [Y/n/q] ", default: "y").lowercased() {
            case "q":            return .quit
            case "n", "e":       continue                    // edit options → restart the flow
            default:             return .run(assembled)       // y / empty / anything else → run
            }
        }
    }

    // MARK: the step-by-step collection

    /// Ask every option question once, returning the assembled options — or nil if the user quit at any prompt.
    private static func collect(io: ConsoleIO, defaults: CLIOptions) -> CLIOptions? {
        var opts = defaults

        // 1) Witness directory — browse to (and USE) the folder holding the witness texts. The browser shows
        //    the files in each folder and only lets you choose one with ≥2 witnesses, so by the time it returns
        //    the directory is valid; the discovery below is the authority and re-asks defensively if it somehow
        //    disagrees (e.g. an unreadable dir).
        io.write("")
        io.write("  1) Witness directory — open folders to find your texts, then USE the one that holds them:")
        guard let dir = DirectoryBrowser.choose(io: io, start: defaults.directory ?? ".",
                                                title: "Witness directory",
                                                requireExisting: true, purpose: .witnesses) else { return nil }
        opts.directory = dir
        opts.explicitFiles = []   // interactive mode discovers from the directory

        let discovered: [WitnessLoader.Discovered]
        do { discovered = try WitnessLoader.discover(inDirectory: dir) }
        catch { io.write("     ⚠️  \((error as? CLIError)?.message ?? "cannot read directory")");
                return collect(io: io, defaults: opts) }
        if discovered.count < 2 {
            io.write("     ⚠️  found \(discovered.count) witness file(s) — need at least 2. Pick another directory.")
            return collect(io: io, defaults: opts)
        }
        io.write("     Using \(discovered.count) witnesses:")
        for (i, d) in discovered.enumerated() { io.write("       [\(i + 1)] \(d.siglum)") }
        let sigla = discovered.map { $0.siglum }

        // 2) Which witnesses? "all" or a 1-based index list ("1,3,4").
        guard let sel = askAllowingQuit(io, "  2) Which witnesses? (all, or e.g. 1,3)", default: "all") else { return nil }
        let chosen = parseSelection(sel, sigla: sigla)
        opts.order = (chosen.count == sigla.count && chosen == sigla) ? nil : chosen   // nil = all, in order
        let effectiveOrder = chosen

        // 3) Base (copy-text)?
        guard let base = askAllowingQuit(io, "  3) Base (copy-text)?", default: effectiveOrder.first ?? sigla[0]) else { return nil }
        opts.base = (base == effectiveOrder.first) ? nil : base   // nil = first in order

        // 4) Order? (comma list of sigla, or accept the current order)
        guard let orderIn = askAllowingQuit(io, "  4) Order?", default: effectiveOrder.joined(separator: ",")) else { return nil }
        let orderList = orderIn.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if !orderList.isEmpty && orderList != effectiveOrder { opts.order = orderList }

        // 5) Comparison mode?
        guard let mode = askChoice(io, "  5) Comparison mode?",
                                   options: ["Substantive (fold accidentals)", "Diplomatic (spelling + punctuation)"],
                                   default: defaults.mode == .diplomatic ? 2 : 1) else { return nil }
        opts.mode = (mode == 2) ? .diplomatic : .substantive

        // 6) Pagination?
        guard let pag = askChoice(io, "  6) Pagination?",
                                  options: ["Source markers", "N lines/page", "Through-numbered"],
                                  default: 1) else { return nil }
        switch pag {
        case 2:
            guard let n = askAllowingQuit(io, "     lines per page?", default: "40"), let v = Int(n), v > 0 else {
                opts.pagination = .sourceMarkers; break
            }
            opts.pagination = .linesPerPage(v)
        case 3: opts.pagination = .throughNumbered
        default: opts.pagination = .sourceMarkers
        }

        // 7) Format?
        guard let fmt = askChoice(io, "  7) Format?", options: ["text", "json", "csv", "html (interactive viewer)"],
                                  default: (["text": 1, "json": 2, "csv": 3, "html": 4][defaults.format.rawValue]) ?? 1) else { return nil }
        opts.format = [1: .text, 2: .json, 3: .csv, 4: .html][fmt] ?? .text

        // 8) Export the results to a folder (html + json + reports), or just print to the console?
        guard let doExport = askChoice(io, "  8) Save results to a folder?",
                                       options: ["No — print to the console only",
                                                 "Yes — choose an output folder (writes collation.html, collation.json, reports)"],
                                       default: defaults.outDir == nil ? 1 : 2) else { return nil }
        if doExport == 2 {
            // Browse-and-pick the output folder — a to-be-created path typed at the prompt is accepted.
            io.write("")
            io.write("     Open folders to the save location, then SAVE HERE — or type a new folder name to create:")
            guard let out = DirectoryBrowser.choose(io: io, start: defaults.outDir ?? ".",
                                                    title: "Output folder",
                                                    requireExisting: false, purpose: .output) else { return nil }
            opts.outDir = out
        } else {
            opts.outDir = nil
        }

        return opts
    }

    // MARK: prompt helpers

    /// Ask, showing `[default]`; empty input accepts the default.
    private static func ask(_ io: ConsoleIO, _ prompt: String, default def: String) -> String {
        let answer = io.readLine(prompt: "\(prompt) [\(def)] › ") ?? ""
        let trimmed = answer.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? def : trimmed
    }

    /// Like `ask`, but returns nil when the user types `q` or hits EOF — so callers can propagate a quit.
    private static func askAllowingQuit(_ io: ConsoleIO, _ prompt: String, default def: String) -> String? {
        guard let answer = io.readLine(prompt: "\(prompt) [\(def)] › ") else { return nil }   // EOF → quit
        let trimmed = answer.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased() == "q" { return nil }
        return trimmed.isEmpty ? def : trimmed
    }

    /// A numbered-choice prompt; returns the 1-based selection, or nil on quit/EOF.
    private static func askChoice(_ io: ConsoleIO, _ prompt: String, options: [String], default def: Int) -> Int? {
        io.write(prompt)
        for (i, o) in options.enumerated() { io.write("       [\(i + 1)] \(o)") }
        guard let raw = askAllowingQuit(io, "     choose", default: String(def)) else { return nil }
        guard let n = Int(raw), (1...options.count).contains(n) else { return def }   // invalid → default
        return n
    }

    // MARK: selection parsing

    /// Parse a "which witnesses" answer into an ordered siglum list. "all" (or empty) → every siglum in order;
    /// otherwise a comma list of 1-based indices (out-of-range indices ignored). Deterministic, order-preserving.
    static func parseSelection(_ input: String, sigla: [String]) -> [String] {
        let s = input.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty || s == "all" { return sigla }
        var picked: [String] = []
        for part in input.split(separator: ",") {
            if let idx = Int(part.trimmingCharacters(in: .whitespaces)), (1...sigla.count).contains(idx) {
                let siglum = sigla[idx - 1]
                if !picked.contains(siglum) { picked.append(siglum) }
            }
        }
        return picked.isEmpty ? sigla : picked
    }

    // MARK: summary

    /// A one-line summary of the assembled run (used before the confirm).
    static func summary(_ o: CLIOptions) -> String {
        let witnesses = o.order.map { "\($0.count) witnesses" } ?? "all witnesses"
        let base = o.base.map { "base \($0)" } ?? "base = first"
        let pag: String = {
            switch o.pagination {
            case .sourceMarkers: return "source pages"
            case .linesPerPage(let n): return "\(n) lines/page"
            case .throughNumbered: return "through-numbered"
            }
        }()
        let dest = o.outDir.map { "→ \($0)" } ?? "→ console"
        return "\(witnesses) · \(base) · \(o.mode.rawValue) · \(pag) · \(o.format.rawValue) \(dest)"
    }
}
