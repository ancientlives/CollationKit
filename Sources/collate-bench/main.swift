import CollationKit
import Foundation

// collate-bench — the BENCHMARK HARNESS (BACKLOG B3).
//
// The paper's evaluation needs *measured* cost, not just the characterisation in DEVELOPMENT_LOG. This sweeps
// the three variables that actually drive the engine's cost and emits a CSV + a readable table:
//
//   • length         — witness word count. The Needleman–Wunsch core is O(n·m), bounded by anchor chunking.
//   • lexical diversity — the fraction of DISTINCTIVE tokens. This sets anchor density: high-diversity prose
//                       has many unique n-grams so NW is chunked into small regions; low-diversity text
//                       starves the anchor pass and falls back to the banded matrix (the cost cliff the
//                       DEVELOPMENT_LOG 2026-06-28 entry characterised). This is the key non-obvious axis.
//   • witness count   — N for the N-witness variant graph (progressive base-anchored fold, ~linear in N).
//
//   swift run -c release collate-bench                 # default sweep → table + CSV on stdout
//   swift run -c release collate-bench --csv out.csv   # also write the CSV to a file
//   swift run -c release collate-bench --quick         # a smaller, faster sweep (smoke test)
//
// Deterministic: a fixed-seed PRNG generates the corpus, so the *shape* of the numbers is reproducible
// (absolute times are machine-dependent; the harness prints the host + build config so results are
// self-describing). Each point is warmed up then measured over several trials; the MEDIAN is reported to
// damp scheduler noise.

// MARK: - Deterministic PRNG (SplitMix64) — reproducible corpus, no Foundation randomness.

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Corpus generation

/// Generate a witness of `words` words at a given `diversity` in [0,1]: each word is, with probability
/// `diversity`, a DISTINCTIVE token (drawn from a large indexed pool → unique n-grams → dense anchors); else
/// a COMMON function word from a tiny pool (→ repetition → sparse anchors → the banded fallback at the low
/// end). Paragraph breaks every ~40 words; a page break every `wordsPerPage` words.
func makeWitness(words: Int, diversity: Double, wordsPerPage: Int, rng: inout SplitMix64) -> String {
    let common = ["the", "and", "of", "a", "to", "in", "that", "it", "was", "he"]
    var out = ""
    out.reserveCapacity(words * 7)
    for i in 0..<words {
        let pickDistinctive = Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0) < diversity
        if pickDistinctive {
            out += "tok\(i)"            // index-suffixed → globally unique → a reliable anchor
        } else {
            out += common[Int(rng.next() % UInt64(common.count))]
        }
        if (i + 1) % wordsPerPage == 0 && i + 1 < words { out += "\n\n<!-- page break -->\n\n" }
        else if (i + 1) % 12 == 0 { out += ".\n\n" }
        else { out += " " }
    }
    return out
}

/// Derive a lightly-edited witness from `text`: substitute ~`editRate` of the DISTINCTIVE tokens. Keeps the
/// witnesses alignable (most anchors survive) while giving the classifier real variants to find.
func editWitness(_ text: String, editRate: Double, salt: Int, rng: inout SplitMix64) -> String {
    var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    for k in words.indices where words[k].hasPrefix("tok") {
        if Double(rng.next() >> 11) * (1.0 / 9_007_199_254_740_992.0) < editRate {
            words[k] = "rev\(salt)_\(k)"
        }
    }
    return words.joined(separator: " ")
}

// MARK: - Measurement

/// Anchor density proxy: the fraction of comparable tokens whose normalized key is UNIQUE in the witness —
/// i.e. how many candidate landmarks the anchor pass has to chunk NW. Reported alongside time because it is
/// the variable that explains the time (high density → cheap; low density → the banded cliff).
func uniqueKeyFraction(_ text: String) -> Double {
    let tokens = Tokenizer.tokenize(text, with: .substantive)
    let keys = tokens.filter { $0.isComparable }.map { $0.normalized }
    guard !keys.isEmpty else { return 0 }
    var counts: [String: Int] = [:]
    for k in keys { counts[k, default: 0] += 1 }
    let uniques = keys.reduce(0) { $0 + (counts[$1] == 1 ? 1 : 0) }
    return Double(uniques) / Double(keys.count)
}

/// Median wall-clock seconds over `trials` runs of `body`, after one warm-up run.
func medianTime(trials: Int, _ body: () -> Void) -> Double {
    body()  // warm up (cache, COW, first-touch)
    var samples: [Double] = []
    samples.reserveCapacity(trials)
    for _ in 0..<trials {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        let end = DispatchTime.now().uptimeNanoseconds
        samples.append(Double(end - start) / 1_000_000_000.0)
    }
    samples.sort()
    return samples[samples.count / 2]
}

// MARK: - Sweep

struct Row {
    let kind: String        // "pairwise" or "graph"
    let words: Int
    let diversity: Double
    let witnesses: Int
    let anchorDensity: Double
    let variants: Int
    let seconds: Double
    var strategy: String = "base-anchored"   // graph rows only: the N-witness merge strategy (B13/B14)
}

let args = Array(CommandLine.arguments.dropFirst())
let quick = args.contains("--quick")
let csvPath: String? = {
    if let i = args.firstIndex(of: "--csv"), i + 1 < args.count { return args[i + 1] }
    return nil
}()

let lengths   = quick ? [500, 2000]            : [500, 1000, 2000, 4000, 8000]
let diversities = quick ? [0.2, 0.8]           : [0.1, 0.3, 0.6, 0.9]
let witnessCounts = quick ? [2, 4]             : [2, 3, 5, 8]
let trials    = quick ? 3 : 5
let wordsPerPage = 200
let editRate = 0.05

var rows: [Row] = []

// 1) PAIRWISE sweep: length × diversity (2 witnesses). Isolates the NW/anchor cost vs. the two key axes.
for words in lengths {
    for diversity in diversities {
        var rng = SplitMix64(seed: 0xC011A7E0 ^ UInt64(words) ^ UInt64(diversity * 1000))
        let baseText = makeWitness(words: words, diversity: diversity, wordsPerPage: wordsPerPage, rng: &rng)
        let compText = editWitness(baseText, editRate: editRate, salt: 1, rng: &rng)
        let base = Witness(id: "base", text: baseText)
        let comp = Witness(id: "rev", text: compText)
        let density = uniqueKeyFraction(baseText)
        var variants = 0
        let secs = medianTime(trials: trials) {
            variants = Collation.collate(base: base, compared: comp).variations.count
        }
        rows.append(Row(kind: "pairwise", words: words, diversity: diversity, witnesses: 2,
                        anchorDensity: density, variants: variants, seconds: secs))
    }
}

// 2) GRAPH sweep: witness-count × merge strategy at a fixed mid length & diversity. Isolates the N-witness
//    merge's growth in N, and measures the base-anchored lift vs. the B14 peer MSA on the same inputs (the
//    two-strategy delta an ablation study reports).
let graphWords = quick ? 1000 : 2000
let graphDiversity = 0.6
for n in witnessCounts {
    var rng = SplitMix64(seed: 0x64A09000 ^ UInt64(n))
    let baseText = makeWitness(words: graphWords, diversity: graphDiversity, wordsPerPage: wordsPerPage, rng: &rng)
    var witnesses = [Witness(id: "w0", text: baseText)]
    for j in 1..<n {
        witnesses.append(Witness(id: "w\(j)", text: editWitness(baseText, editRate: editRate, salt: j, rng: &rng)))
    }
    let density = uniqueKeyFraction(baseText)
    for strategy in CollationStrategy.allCases {
        var variants = 0
        let secs = medianTime(trials: trials) {
            variants = Collation.variantGraph(witnesses: witnesses, strategy: strategy).variantNodes.count
        }
        rows.append(Row(kind: "graph", words: graphWords, diversity: graphDiversity, witnesses: n,
                        anchorDensity: density, variants: variants, seconds: secs,
                        strategy: strategy == .baseAnchored ? "base-anchored" : "peer-msa"))
    }
}

// MARK: - Output

func fmt(_ d: Double, _ places: Int) -> String { String(format: "%.\(places)f", d) }
func ms(_ s: Double) -> String { String(format: "%.2f", s * 1000) }
func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : String(repeating: " ", count: w - s.count) + s }
func cols(_ cells: [(String, Int)]) -> String { cells.map { pad($0.0, $0.1) }.joined(separator: "  ") }

// Self-describing header so a recorded run is interpretable later.
let host = ProcessInfo.processInfo
#if DEBUG
let buildConfig = "debug (run with -c release for representative numbers)"
#else
let buildConfig = "release"
#endif
print("# CollationKit benchmark — collate-bench")
print("# host: \(host.operatingSystemVersionString); cores: \(host.activeProcessorCount); build: \(buildConfig)")
print("# trials per point: \(trials) (median reported); editRate: \(editRate); wordsPerPage: \(wordsPerPage)")
print("")

// Human-readable table.
print("PAIRWISE  (2 witnesses; time vs. length × lexical diversity)")
print(cols([("words", 8), ("diversity", 9), ("anchorDensity", 13), ("variants", 9), ("time(ms)", 10)]))
for r in rows where r.kind == "pairwise" {
    print(cols([("\(r.words)", 8), (fmt(r.diversity, 2), 9), (fmt(r.anchorDensity, 3), 13),
                ("\(r.variants)", 9), (ms(r.seconds), 10)]))
}
print("")
print("GRAPH  (N-witness merge; \(graphWords) words, diversity \(graphDiversity); time vs. witness count × strategy)")
print(cols([("witnesses", 10), ("strategy", 14), ("anchorDensity", 13), ("variants", 9), ("time(ms)", 10)]))
for r in rows where r.kind == "graph" {
    print(cols([("\(r.witnesses)", 10), (r.strategy, 14), (fmt(r.anchorDensity, 3), 13),
                ("\(r.variants)", 9), (ms(r.seconds), 10)]))
}

// CSV (always to stdout block; optionally to a file).
var csv = "kind,words,diversity,witnesses,strategy,anchor_density,variants,seconds\n"
for r in rows {
    csv += "\(r.kind),\(r.words),\(fmt(r.diversity,2)),\(r.witnesses),\(r.strategy),\(fmt(r.anchorDensity,4)),\(r.variants),\(fmt(r.seconds,6))\n"
}
print("\n# CSV\n" + csv, terminator: "")
if let path = csvPath {
    try? csv.write(toFile: path, atomically: true, encoding: .utf8)
    FileHandle.standardError.write(Data("wrote CSV to \(path)\n".utf8))
}
