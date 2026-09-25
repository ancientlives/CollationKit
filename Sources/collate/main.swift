import CollateCLI
import Foundation

// collate — the thin shell around the testable `CollateCLI` core (BACKLOG B9, CLI_PLAN §2).
//
// This file is a tiny adapter: it binds the core's abstract `OutputSink` to real stdout/stderr and maps the
// returned exit code to `exit(...)`. ALL logic — parsing, discovery, collation, formatting, export — lives in
// `CollateCLI` so it can be unit-tested without a terminal. Keep this file trivial.

struct StdIO: OutputSink {
    func out(_ s: String) { print(s) }
    func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
}

// A real terminal console for the interactive menu (nil-safe: the core only uses it for the no-subcommand
// interactive path). Non-interactive commands ignore it.
let code = CollateCLI.main(Array(CommandLine.arguments.dropFirst()), sink: StdIO(), console: TerminalConsoleIO())
exit(code)
