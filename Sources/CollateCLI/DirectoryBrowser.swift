import CollationKit
import Foundation

// MARK: - Interactive directory picker (BACKLOG B9 phase 3, CLI_PLAN §5)
//
// A browse-and-pick navigator over the `ConsoleIO` seam — no real terminal — so the menu lets the user *see*
// where they are and *choose* a folder the way file-oriented CLI tools do, instead of typing a full path.
// Redesigned 2026-07-07 because the first cut was clumsy (it hid the files, and it was unclear when
// a folder gets chosen; it also mis-used `.` for "up").
//
// What the user sees at each step: the current path, then a UNIFIED numbered list of the immediate
// SUBFOLDERS (each shown with a trailing `/`), followed by the witness FILES already in this folder (shown so
// you can see what you'd collate — sizes included; they are informational, not numbered). A persistent action
// line spells out every command, so "how do I choose this folder" is never a guess:
//
//   <number>   → go INTO that subfolder
//   ../ (or ..) → go UP a level (the Unix relative-parent form)
//   u  (or ↵)  → USE this folder for the collation (the explicit "choose" action)
//   ~ / <path> → jump to a typed/pasted path (absolute, ~-relative, or relative to here — `.`/`..` segments
//                are resolved, e.g. `../other`)
//   q          → cancel
//
// Starts at the caller's directory (CWD when `collate` is invoked globally with no `--dir`; `--dir` overrides),
// so a tool on $PATH behaves like every other CLI: it begins where you are and lets you go elsewhere. `current`
// is kept ABSOLUTE and standardized throughout — a relative `current` (e.g. ".") made `..` jump to `/` instead
// of the cwd's parent.
//
// `requireExisting`: the witness directory must exist AND is best chosen once it actually holds witness files
// (the "USE this folder" line reports the count, and selecting an empty folder warns but is allowed — the outer
// menu re-asks on <2). The export folder passes `requireExisting: false`, so a not-yet-created folder name typed
// at the prompt is accepted and the exporter makes it.
enum DirectoryBrowser {

    /// Browse from `start` and return the chosen directory path, or nil if the user cancelled. `title` labels
    /// the prompt (e.g. "Witness directory"). `purpose` tailors the "use this folder" wording (witness vs
    /// output). See the grammar above.
    static func choose(io: ConsoleIO, start: String, title: String,
                       requireExisting: Bool, purpose: Purpose = .witnesses) -> String? {
        let fm = FileManager.default
        var current = normalizedExistingDir(Paths.expand(start), fallback: fm.currentDirectoryPath)

        while true {
            let subdirs = subdirectories(of: current)
            let witnessFiles = witnessFiles(in: current)

            io.write("")
            io.write("     \(title):  \(abbreviate(current))")

            // Folders — numbered, the things you can descend into.
            if subdirs.isEmpty {
                io.write("       (no subfolders)")
            } else {
                for (i, name) in subdirs.enumerated() { io.write("       \(i + 1))  \(name)/") }
            }
            // Witness files already here — informational, so you can see what "use this folder" would collate.
            if !witnessFiles.isEmpty {
                io.write("       · \(witnessFiles.count) witness file(s) here:")
                for f in witnessFiles { io.write("           \(f.name)   (\(f.size))") }
            }

            // The persistent, explicit action line — every command spelled out. `../` reads as "up a level"
            // (the Unix relative-parent form); `<n>` opens a listed folder; a typed path jumps anywhere.
            let use = purpose.useLabel(fileCount: witnessFiles.count)
            io.write("       \(use)   ·   ../ up a level   ·   <n> open folder   ·   type a path   ·   q cancel")

            guard let raw = io.readLine(prompt: "     › ") else { return nil }     // EOF → cancel
            let answer = raw.trimmingCharacters(in: .whitespaces)

            switch answer.lowercased() {
            case "q":
                return nil
            case "u", "":                       // explicit "use this folder" (Enter is the same, for speed)
                if purpose == .witnesses, witnessFiles.count < 2 {
                    io.write("       ⚠️  this folder has \(witnessFiles.count) witness file(s) — "
                             + "collation needs at least 2. Open a subfolder, or `../` up a level, to find your texts.")
                    continue                    // stay in the browser rather than bouncing out to a re-ask
                }
                return current
            case "..", "../":               // "up a level" — accept both the bare and trailing-slash forms
                current = parent(of: current)
            default:
                if let n = Int(answer), (1...subdirs.count).contains(n) {
                    current = (current as NSString).appendingPathComponent(subdirs[n - 1])   // open a folder
                } else {
                    // A typed/pasted path — absolute, ~-relative, or relative to the current folder.
                    let resolved = resolve(answer, relativeTo: current)
                    var isDir: ObjCBool = false
                    let exists = fm.fileExists(atPath: resolved, isDirectory: &isDir)
                    if exists && isDir.boolValue {
                        current = resolved                       // navigate into the typed directory
                    } else if exists && !isDir.boolValue {
                        io.write("       ⚠️  not a directory: \(resolved)")
                    } else if requireExisting {
                        io.write("       ⚠️  no such directory: \(resolved)")
                    } else {
                        return resolved                          // export target: accept a to-be-created path
                    }
                }
            }
        }
    }

    /// What the chosen folder is for — tailors the "use this folder" action wording.
    enum Purpose { case witnesses, output
        func useLabel(fileCount: Int) -> String {
            switch self {
            case .witnesses:
                return fileCount >= 2 ? "u USE THIS FOLDER (\(fileCount) witnesses)"
                                      : "u use this folder"
            case .output:
                return "u SAVE HERE"
            }
        }
    }

    // MARK: helpers

    /// The immediate subdirectory names of `dir` (visible only — skip dotfiles), sorted for deterministic order.
    private static func subdirectories(of dir: String) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return entries.filter { name in
            guard !name.hasPrefix(".") else { return false }
            var isDir: ObjCBool = false
            let full = (dir as NSString).appendingPathComponent(name)
            return fm.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    /// The witness files (`.txt`/`.md`) directly in `dir`, with a human-readable size — the same extensions
    /// `WitnessLoader.discover` picks up, so what the picker shows is exactly what would be collated.
    private static func witnessFiles(in dir: String) -> [(name: String, size: String)] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return entries.filter { name in
            guard !name.hasPrefix(".") else { return false }
            let ext = (name as NSString).pathExtension.lowercased()
            return WitnessLoader.witnessExtensions.contains(ext)
        }.sorted().map { name in
            let full = (dir as NSString).appendingPathComponent(name)
            let bytes = (try? fm.attributesOfItem(atPath: full)[.size] as? Int) ?? nil
            return (name, humanSize(bytes))
        }
    }

    private static func parent(of dir: String) -> String {
        let p = (dir as NSString).deletingLastPathComponent
        return p.isEmpty ? "/" : p
    }

    /// Resolve a typed path to an ABSOLUTE, standardized path: absolute or `~` as given; otherwise relative to
    /// `base` (which is already absolute), with `.`/`..` segments collapsed so e.g. `../other` works.
    private static func resolve(_ path: String, relativeTo base: String) -> String {
        let expanded = Paths.expand(path)
        let joined = (expanded as NSString).isAbsolutePath
            ? expanded
            : (base as NSString).appendingPathComponent(expanded)
        return (joined as NSString).standardizingPath
    }

    /// The starting directory as an ABSOLUTE, standardized path — so `..` and descent always operate on a real
    /// absolute path (a relative `current` like "." made `..` jump to `/` instead of the cwd's parent). Resolves
    /// a relative `path` against the current working directory; falls back to `fallback` if it isn't a directory.
    private static func normalizedExistingDir(_ path: String, fallback: String) -> String {
        let absolute = absolutePath(path, cwd: fallback)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: absolute, isDirectory: &isDir), isDir.boolValue { return absolute }
        return absolutePath(fallback, cwd: fallback)
    }

    /// Make `path` absolute (relative to `cwd`) and standardize it (collapses `.`/`..` segments, trailing `/`).
    private static func absolutePath(_ path: String, cwd: String) -> String {
        let base = (path as NSString).isAbsolutePath ? path : (cwd as NSString).appendingPathComponent(path)
        return (base as NSString).standardizingPath
    }

    /// Show the home directory as `~` for a shorter, familiar path line.
    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// A compact human-readable byte size (KB/MB), matching the tone of other CLI file listers.
    private static func humanSize(_ bytes: Int?) -> String {
        guard let b = bytes else { return "?" }
        if b < 1024 { return "\(b) B" }
        let kb = Double(b) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024)
    }
}
