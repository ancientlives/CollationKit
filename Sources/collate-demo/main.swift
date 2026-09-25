import CollationKit
import Foundation

// collate-demo — a CLI preview of how collation RENDERS, and a harness for running the engine on ARBITRARY
// texts (so the engine can be exercised abstractly, not only on the static built-in fixtures).
//
//   swift run collate-demo                       # the built-in six-edition example (full texts + report)
//   swift run collate-demo a.txt b.txt [c.txt …] # collate your own files (first = base witness)
//   swift run collate-demo --accidentals a.txt b.txt   # also report spelling/case (accidental) variants
//   swift run collate-demo --lines-per-page 40 a.txt b.txt   # cite against a 40-line printed page
//   swift run collate-demo --through-numbered a.txt b.txt    # continuous line numbering (no per-page reset)
//
// For your own files, each file is one witness; its id is the filename. With ≥2 files it prints the located
// variant report for each successive pair plus the N-witness apparatus and synopsis.

let rawArgs = Array(CommandLine.arguments.dropFirst())
let recordAccidentals = rawArgs.contains("--accidentals")
let recordPunctuation = rawArgs.contains("--record-punctuation")   // diplomatic: report punctuation variants
let throughNumbered = rawArgs.contains("--through-numbered")
let emitJSON = rawArgs.contains("--json")   // emit the cross-language JSON interchange instead of text
// --lines-per-page N : cite against a uniform printed page of N text lines (else source markers).
var linesPerPage: Int? = nil
if let idx = rawArgs.firstIndex(of: "--lines-per-page"), idx + 1 < rawArgs.count {
    linesPerPage = Int(rawArgs[idx + 1])
}
let fileArgs = rawArgs.filter { !$0.hasPrefix("--") && Int($0) == nil }

let pagination: PaginationModel = {
    if let n = linesPerPage { return .printedPage(linesPerPage: n) }
    if throughNumbered { return .throughNumbered }
    return .default
}()

func rule(_ title: String) { print("\n" + String(repeating: "═", count: 78)); print(title); print(String(repeating: "═", count: 78)) }

func witnessesFromFiles(_ paths: [String]) -> [Witness] {
    paths.compactMap { path in
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("⚠️  could not read \(path)\n".utf8)); return nil
        }
        let id = (path as NSString).lastPathComponent
        return Witness(id: id, text: text)
    }
}

// Pick the witness set + normalizer: custom files if given, else the built-in six-edition example.
let usingCustom = fileArgs.count >= 2
let witnesses: [Witness] = usingCustom ? witnessesFromFiles(fileArgs) : Samples.sixEditions
let normalizer = usingCustom ? Normalizer.substantive : Samples.gbUSNormalizer

guard witnesses.count >= 2 else {
    print("Need at least two witnesses. Pass ≥2 text files, or run with no args for the built-in example.")
    exit(1)
}

// --json: emit the cross-language interchange (the N-witness graph + each successive pair) and stop. This is
// the shape a web/WASM front end or a comparison harness would consume.
if emitJSON {
    print(CollationJSON.outputString(witnesses: witnesses, normalizer: normalizer,
                                     pagination: pagination, recordAccidentals: recordAccidentals,
                                     recordPunctuation: recordPunctuation))
    exit(0)
}

// 1) Full witness texts — so the reader can see exactly what is being collated.
rule("WITNESSES (full text)")
for w in witnesses {
    print("\n── \(w.id) " + String(repeating: "─", count: max(0, 72 - w.id.count)))
    print(w.text)
}

// 2) Located variant report for each successive pair — WHERE each change is (page · line · word).
rule("LOCATED VARIANT REPORT (successive pairs)")
for i in 1..<witnesses.count {
    let r = Collation.collate(base: witnesses[i - 1], compared: witnesses[i],
                              normalizer: normalizer, recordAccidentals: recordAccidentals,
                              recordPunctuation: recordPunctuation, pagination: pagination)
    print("\n" + Report.located(r))
}

// 3) N-witness critical apparatus (base = first witness).
let graph = Collation.variantGraph(witnesses: witnesses, normalizer: normalizer, pagination: pagination)
rule("CRITICAL APPARATUS  (base = \(graph.baseID))")
let entries = Apparatus.entries(from: graph)
print(entries.isEmpty ? "(no points of variance)" : Apparatus.plainText(entries))

// 4) Synoptic parallel columns (variant rows only, for a compact view).
rule("SYNOPTIC COLUMNS  (rows where witnesses differ)")
let table = Synopsis.table(from: graph, witnessOrder: witnesses.map { $0.id })
print(table.variantRows.isEmpty ? "(witnesses agree everywhere)"
                                 : Synopsis.plainText(table.variantsOnly, columnWidth: 12))
