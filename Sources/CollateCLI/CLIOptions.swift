import CollationKit
import Foundation

// MARK: - Parsed run configuration (BACKLOG B9, CLI_PLAN §4)
//
// `CLIOptions` is a value type describing one `collate run`. Flag parsing and validation live here so the
// interactive menu (a later phase) and the flag mode produce the SAME model — one config, two front doors.
// No engine logic: this only selects witnesses/options and hands them to `CollationRunner`, which is the one
// place that calls `CollationKit`.

/// What comparison view to produce — the normaliser + accidental overlays preset (CLI_PLAN §4).
public enum ComparisonMode: String, Equatable {
    case substantive   // fold accidentals; only meaningful (substantive) variation surfaces (default)
    case diplomatic    // also report spelling/case + punctuation accidentals (the diplomatic view)
}

/// The pagination/citation model choice, mirroring `PaginationModel` but as a flat CLI option.
public enum PaginationChoice: Equatable {
    case sourceMarkers               // page breaks from source markers (default)
    case linesPerPage(Int)           // a uniform printed page of N text lines
    case throughNumbered             // continuous line numbering (no per-page reset)

    var model: PaginationModel {
        switch self {
        case .sourceMarkers:        return .default
        case .linesPerPage(let n):  return .printedPage(linesPerPage: n)
        case .throughNumbered:      return .throughNumbered
        }
    }
}

/// The output encoding for console + export (CLI_PLAN §6). The JSON interchange is ALWAYS written on export,
/// whatever this is, so a run is reproducible/consumable downstream. `html` (B8) is the interactive
/// collation viewer — a single self-contained page (perspective tabs, aligned/variant highlighting, an
/// explorable variant panel); it is also ALWAYS written on export as `collation.html`.
public enum OutputFormat: String, Equatable, CaseIterable {
    case text, json, csv, html
}

/// A fully-validated run configuration.
public struct CLIOptions: Equatable {
    public var directory: String?         // discover witnesses here (nil → explicit files only)
    public var explicitFiles: [String]    // explicit witness paths (first = base unless `base` overrides)
    public var useAll: Bool               // with a directory: use every discovered file
    public var base: String?              // base siglum (copy-text); nil → first in order
    public var order: [String]?           // explicit witness order (sigla); nil → discovery/args order
    public var mode: ComparisonMode
    public var recordAccidentals: Bool    // report spelling/case accidentals
    public var recordPunctuation: Bool    // report punctuation accidentals (diplomatic overlay)
    public var pagination: PaginationChoice
    public var format: OutputFormat
    public var outDir: String?            // export directory (nil → console only)
    public var strategy: CollationStrategy // N-witness merge strategy (default .baseAnchored; see PAPER_NOTES §5.4)
    public var scoring: ScoringPreset      // alignment scoring preset (default .prose; B7, see ALGORITHMS §10)
    public var lexiconPath: String?        // B10: translation lexicon file (nil → no cross-language anchoring)

    public init(directory: String? = nil, explicitFiles: [String] = [], useAll: Bool = false,
                base: String? = nil, order: [String]? = nil, mode: ComparisonMode = .substantive,
                recordAccidentals: Bool = false, recordPunctuation: Bool = false,
                pagination: PaginationChoice = .sourceMarkers, format: OutputFormat = .text,
                outDir: String? = nil, strategy: CollationStrategy = .baseAnchored,
                scoring: ScoringPreset = .prose, lexiconPath: String? = nil) {
        self.directory = directory; self.explicitFiles = explicitFiles; self.useAll = useAll
        self.base = base; self.order = order; self.mode = mode
        self.recordAccidentals = recordAccidentals; self.recordPunctuation = recordPunctuation
        self.pagination = pagination; self.format = format; self.outDir = outDir
        self.strategy = strategy; self.scoring = scoring; self.lexiconPath = lexiconPath
    }

    /// The `.diplomatic` preset turns BOTH accidental overlays on and uses the diplomatic normaliser; the
    /// substantive default folds them. Kept as a computed helper so the runner picks the right engine inputs.
    public var normalizer: Normalizer { mode == .diplomatic ? .diplomatic : .substantive }
    public var effectiveRecordAccidentals: Bool { recordAccidentals || mode == .diplomatic }
    public var effectiveRecordPunctuation: Bool { recordPunctuation || mode == .diplomatic }
}

/// A CLI usage/validation error with a clear message and a POSIX-style exit code (CLI_PLAN §9 Stage B will
/// refine the catalogue; the codes here are the stable subset the tests assert).
public struct CLIError: Error, Equatable {
    public enum Kind: Int, Equatable { case usage = 1, witnesses = 2, io = 3 }
    public let kind: Kind
    public let message: String
    public init(_ kind: Kind, _ message: String) { self.kind = kind; self.message = message }
}

// MARK: - Flag parsing

public enum CLIParser {

    /// Parse `run`-mode arguments (everything after the `run` subcommand) into `CLIOptions`. Hand-rolled to
    /// keep the zero-dependency stance (CLI_PLAN §2). Unknown flags are a usage error.
    public static func parseRun(_ args: [String]) throws -> CLIOptions {
        var opts = CLIOptions()
        var i = 0
        func next(_ flag: String) throws -> String {
            i += 1
            guard i < args.count else { throw CLIError(.usage, "\(flag) requires a value") }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--dir":               opts.directory = try next(a)
            case "--all":               opts.useAll = true
            case "--base":              opts.base = try next(a)
            case "--order":             opts.order = try next(a).split(separator: ",").map(String.init)
            case "--substantive":       opts.mode = .substantive
            case "--diplomatic":        opts.mode = .diplomatic
            case "--accidentals":       opts.recordAccidentals = true
            case "--record-punctuation": opts.recordPunctuation = true
            case "--lines-per-page":
                guard let n = Int(try next(a)), n > 0 else { throw CLIError(.usage, "--lines-per-page needs a positive integer") }
                opts.pagination = .linesPerPage(n)
            case "--through-numbered":  opts.pagination = .throughNumbered
            case "--format":
                let v = try next(a)
                guard let f = OutputFormat(rawValue: v) else { throw CLIError(.usage, "unknown --format '\(v)' (text|json|csv|html)") }
                opts.format = f
            case "--out":               opts.outDir = try next(a)
            case "--strategy":
                let v = try next(a)
                guard let s = strategy(fromCLIValue: v) else {
                    throw CLIError(.usage, "unknown --strategy '\(v)' (base-anchored|peer-msa)")
                }
                opts.strategy = s
            case "--scoring":
                let v = try next(a)
                guard let p = ScoringPreset(rawValue: v.lowercased()) else {
                    throw CLIError(.usage, "unknown --scoring '\(v)' (prose|verse)")
                }
                opts.scoring = p
            case "--lexicon":           opts.lexiconPath = try next(a)
            default:
                if a.hasPrefix("--") { throw CLIError(.usage, "unknown flag '\(a)'") }
                opts.explicitFiles.append(a)   // a positional argument = a witness path
            }
            i += 1
        }
        return opts
    }

    /// Map a user-facing `--strategy` value to a `CollationStrategy`. Accepts friendly aliases so the CLI isn't
    /// tied to the raw Swift case names: `base-anchored`/`base`/`baseanchored` and `peer-msa`/`peer`/`msa`.
    static func strategy(fromCLIValue v: String) -> CollationStrategy? {
        switch v.lowercased() {
        case "base-anchored", "base", "baseanchored", "base_anchored": return .baseAnchored
        case "peer-msa", "peer", "msa", "peermsa", "peer_msa":         return .peerMSA
        default:                                                       return nil
        }
    }

    /// Validate the *shape* of the options independent of the filesystem (base ∈ order if both given, a
    /// witness source is present, etc.). Filesystem checks (files exist, ≥2 witnesses, out dir writable) happen
    /// in the runner where the witnesses are actually loaded.
    public static func validate(_ opts: CLIOptions) throws {
        if opts.directory == nil && opts.explicitFiles.isEmpty {
            throw CLIError(.usage, "no witnesses: `run` needs witness files (or --dir <path> with --all/--order). "
                                 + "For the interactive menu — browse to a folder, pick options — run `collate` with no `run`.")
        }
        if let base = opts.base, let order = opts.order, !order.contains(base) {
            throw CLIError(.usage, "--base '\(base)' is not among --order \(order.joined(separator: ","))")
        }
        // Both strategies are implemented (B14 landed the peer MSA), but keep the guard so a future reserved
        // strategy fails loudly rather than silently falling back — a scripted run must never believe it
        // collated with a strategy that didn't run.
        if !opts.strategy.isAvailable {
            throw CLIError(.usage, "--strategy \(opts.strategy.rawValue) is not available in this build.")
        }
    }
}
