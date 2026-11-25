import CollationKit
import Foundation

// MARK: - Witness discovery + loading (BACKLOG B9, CLI_PLAN §2)
//
// Turns a `CLIOptions` witness source (a directory of files, or explicit paths) into an ordered `[Witness]`
// the engine collates. All *terminal* concerns (reading files, ordering, base selection) live here, never in
// the engine. A witness's id is its filename stem (e.g. `MS.txt` → `MS`), which is what `--base`/`--order`
// reference.
//
// This is pure I/O + selection; it calls no engine algorithm. Errors are `CLIError`s with clear messages and
// stable exit codes so the shell can map them.

/// Path handling shared by every place the CLI accepts a filesystem path (witness files, `--dir`, `--out`,
/// `--lexicon`, the menu's export prompt). `~` is a SHELL expansion: a path typed at an interactive prompt
/// (the menu) or quoted on the command line arrives literally, and Foundation does not expand it — a literal
/// `~/collations` directory silently appears in the cwd and "the files aren't in the defined directory".
public enum Paths {
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

public enum WitnessLoader {

    /// The file extensions treated as witness text. Kept small and explicit (CLI_PLAN §5: non-text skipped).
    public static let witnessExtensions: Set<String> = ["txt", "md"]

    /// A discovered candidate: its siglum (filename stem) and absolute path.
    public struct Discovered: Equatable {
        public let siglum: String
        public let path: String
    }

    /// Discover witness files in a directory, sorted by filename (deterministic). Non-text files are skipped.
    public static func discover(inDirectory rawDir: String) throws -> [Discovered] {
        let dir = Paths.expand(rawDir)
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            throw CLIError(.io, "not a directory: \(dir)")
        }
        let entries: [String]
        do { entries = try fm.contentsOfDirectory(atPath: dir) }
        catch { throw CLIError(.io, "cannot read directory \(dir): \(error.localizedDescription)") }
        return entries
            .filter { witnessExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted()
            .map { name in
                Discovered(siglum: (name as NSString).deletingPathExtension,
                           path: (dir as NSString).appendingPathComponent(name))
            }
    }

    /// Resolve `CLIOptions` into the final ordered witness set, applying discovery, `--order`, and `--base`.
    /// Validates the filesystem-dependent rules (≥2 witnesses; base/order sigla exist; files readable & UTF-8).
    public static func load(_ opts: CLIOptions) throws -> [Witness] {
        // 1) Gather (siglum, path) candidates from the directory and/or explicit files.
        var candidates: [Discovered] = []
        if let dir = opts.directory {
            candidates = try discover(inDirectory: dir)
        }
        for rawPath in opts.explicitFiles {
            let path = Paths.expand(rawPath)
            let siglum = (path as NSString).lastPathComponent as NSString
            candidates.append(Discovered(siglum: siglum.deletingPathExtension, path: path))
        }
        // Witness ids (file names without extension) must be unique: two witnesses with one id merged their
        // readings and corrupted the reports and the viewer's tabs (release 1 review, B13).
        var pathBySiglum: [String: String] = [:]
        for c in candidates {
            if let earlier = pathBySiglum[c.siglum] {
                throw CLIError(.witnesses, earlier == c.path
                    ? "'\(c.path)' is given twice"
                    : "two witnesses have the id '\(c.siglum)' (\(earlier) and \(c.path)); "
                      + "a witness id is the file name without its extension, so rename one of the files")
            }
            pathBySiglum[c.siglum] = c.path
        }
        if let order = opts.order, let dup = order.first(where: { s in order.filter { $0 == s }.count > 1 }) {
            throw CLIError(.witnesses, "--order names '\(dup)' more than once")
        }
        // A directory with neither --all nor --order/explicit files: default to all discovered (friendly).
        // (A subset selection by number is an interactive-menu feature, phase 3.)

        // 2) Apply an explicit --order if given (also acts as a subset filter); else keep discovery/arg order.
        var ordered: [Discovered]
        if let order = opts.order {
            let bySiglum = Dictionary(candidates.map { ($0.siglum, $0) }, uniquingKeysWith: { a, _ in a })
            ordered = try order.map { siglum in
                guard let d = bySiglum[siglum] else {
                    throw CLIError(.witnesses, "--order names '\(siglum)', which is not among the witnesses")
                }
                return d
            }
        } else {
            ordered = candidates
        }

        // 3) Promote --base to the front (it is the copy-text / graph base).
        if let base = opts.base {
            guard let idx = ordered.firstIndex(where: { $0.siglum == base }) else {
                throw CLIError(.witnesses, "--base '\(base)' is not among the witnesses")
            }
            let b = ordered.remove(at: idx)
            ordered.insert(b, at: 0)
        }

        guard ordered.count >= 2 else {
            throw CLIError(.witnesses, "need at least 2 witnesses to collate (found \(ordered.count))")
        }

        // 4) Load the text (UTF-8), erroring clearly on unreadable/non-UTF-8 files.
        return try ordered.map { d in
            guard let text = try? String(contentsOfFile: d.path, encoding: .utf8) else {
                throw CLIError(.io, "cannot read (or not UTF-8): \(d.path)")
            }
            return Witness(id: d.siglum, text: text)
        }
    }
}
