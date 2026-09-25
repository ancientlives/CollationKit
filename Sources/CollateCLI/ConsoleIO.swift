import Foundation

// MARK: - The interactive IO seam (BACKLOG B9 phase 3, CLI_PLAN §2, §5)
//
// The interactive menu is written against this protocol — never against real stdin/stdout — so it can be
// driven in tests by a `ScriptedConsoleIO` (a queued list of answers) with NO terminal. This mirrors the
// project's "pure core, thin shell" stance: `Menu` is pure logic over `ConsoleIO`; the `collate` executable
// binds a real stdin/stdout implementation. (`OutputSink`, used by the non-interactive commands, is the
// output-only subset; `ConsoleIO` adds line input.)

public protocol ConsoleIO: AnyObject {
    /// Print a line to the user (no trailing prompt).
    func write(_ s: String)
    /// Show `prompt` and read one line of input. Returns nil at end-of-input (EOF / no more scripted answers),
    /// which the menu treats as "quit" so a piped/empty stdin can't hang.
    func readLine(prompt: String) -> String?
}

/// A scripted `ConsoleIO` for tests: answers are dequeued in order; `written` records everything shown. When
/// the queue is empty, `readLine` returns nil (EOF) so a menu under test always terminates.
public final class ScriptedConsoleIO: ConsoleIO {
    private var answers: [String]
    public private(set) var written: [String] = []

    public init(_ answers: [String]) { self.answers = answers }

    public func write(_ s: String) { written.append(s) }

    public func readLine(prompt: String) -> String? {
        written.append(prompt)               // record the prompt too, so tests can assert what was asked
        guard !answers.isEmpty else { return nil }
        return answers.removeFirst()
    }

    /// The full transcript (prompts + output) as one string, for convenient test assertions.
    public var transcript: String { written.joined(separator: "\n") }
}

/// The real terminal implementation used by the `collate` shell: prompts on stdout, reads a line from stdin.
public final class TerminalConsoleIO: ConsoleIO {
    public init() {}
    public func write(_ s: String) { print(s) }
    public func readLine(prompt: String) -> String? {
        FileHandle.standardOutput.write(Data(prompt.utf8))
        return Swift.readLine(strippingNewline: true)
    }
}
