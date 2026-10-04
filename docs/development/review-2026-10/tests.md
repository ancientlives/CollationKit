# CollationKit test-suite review (branch `review/release-1`, read-only)

Method: read all 27 suites, the corpus, schema, validate.py, TESTING.md and ci.yml; ran
`swift test --enable-code-coverage` in a scratch build path (macOS, Swift 6.3.2, arm64): **222 tests, 0 failures, 9.34 s**;
`xcrun llvm-cov report` for per-file numbers; probed edge cases with the built `collate` binary and with throwaway
tests in a scratch copy of the repo; built and tested on **Linux in a `swift:6.1-jammy` container** (podman);
ran `validate.py` in a scratch venv and fed it mutated goldens. No repo files or git state touched.

---

## (A) Coverage numbers and gaps

### Per-file line coverage (debug, whole suite)

| file | lines | line cover | function cover | notes |
|---|---:|---:|---:|---|
| CollationKit/Collation.swift | 244 | **38.1 %** | 47.2 % | ~110 lines are `legacyVariantGraph`, which nothing can reach (see below) |
| CollationKit/Apparatus.swift | 92 | 82.6 % | 50.0 % | `ApparatusEntry ==` never called; graph-lemma fallback (l.56) untested |
| CollationKit/CollationNarrative.swift | 193 | 97.4 % | 93.8 % | the "accidental differences were also recorded" sentence (l.100) and the ≥3-item list join (l.199) are never run |
| CollationKit/TokenGraph.swift | 270 | 96.3 % | 85.7 % | |
| CollationKit/CollationJSON.swift | 96 | 95.8 % | 95.2 % | `string(_ graph:)` never called |
| CollationKit/Alignment.swift | 152 | 95.4 % | 88.0 % | banded delete-edge (l.194) and `maxBand` cap (l.213) never run |
| CollationKit/PeerMSA.swift | 338 | 98.2 % | 88.2 % | l.175 (extend a displaced run), l.368 (carrier text-vs-∅ join refusal) never run |
| CollationKit/Transposition.swift | 485 | 98.4 % | 94.0 % | degenerate-length window fallback (l.567–571) never run |
| CollationKit/Tokenizer.swift | 265 | 99.3 % | 100 % | overlapping no-collate skip (l.139) never run |
| CollationKit/Variation.swift | 497 | 99.4 % | 94.6 % | |
| CollationKit/{Token,Pagination,Report,TranslationLexicon}.swift | — | 100 % | 100 % | |
| CollationKit/Synopsis.swift | 62 | 96.8 % | 83.3 % | |
| CollateCLI/ConsoleIO.swift | 15 | 60.0 % | 62.5 % | `TerminalConsoleIO` (needs a real TTY; fine to leave) |
| CollateCLI/CollateCLI.swift | 151 | **82.8 %** | 85.7 % | `list` command, `--lexicon` loading (I/O error, empty-lexicon error) and the debug-build warning are never run |
| CollateCLI/HTMLExport.swift | 227* | 93.4 % | 63.4 % | *only the Swift part counts. The ~1,520-line embedded JS viewer (l.700–2222) has **no automated test at all** |
| CollateCLI/Menu.swift | 177 | 93.8 % | 84.6 % | the `lines per page?` branch and the "<2 witnesses" re-ask path (l.70) never run |
| CollateCLI/WitnessLoader.swift | 90 | 94.4 % | 90.0 % | every error branch untested: not a directory, unknown `--order` siglum, unknown `--base`, unreadable or non-UTF-8 file |
| CollateCLI/CLIOptions.swift | 98 | 98.0 % | 100 % | **`--lines-per-page N` success path (l.113) never run**; only the rejection cases are tested |
| CollateCLI/{CollationRunner,Exporter,DirectoryBrowser} | — | 96–100 % | — | |
| **TOTAL** | 3922 | **92.6 %** | 83.7 % | regions 83.5 % |

(`Samples.swift` and the three executable targets are not in the test binary's coverage map.)

### Public API → tests map: what is untested or only tested indirectly

- **`Collation.legacyVariantGraph`** (Collation.swift:236–~345). The code comment calls it a fallback that "should not happen". No test reaches it and no input can, so it is about 110 lines of untested code shipping in 1.0. Delete it, or move it behind an internal A/B hook and give it a parity test.
- **`CollationJSON.output(witnesses:)` / `outputString(witnesses:)` with `[]` traps.** I confirmed this with a scratch test: `Fatal error: Range requires lowerBound <= upperBound` (`for i in 1..<witnesses.count`, CollationJSON.swift:148). This is a public entry point. The same pattern appears in CollationRunner.swift:61, but there the loader guards it.
- **`Collation.variantGraph(witnesses: [])`** returns an empty graph with `baseID ""`. No test covers it. A single witness works but is only tested under `.peerMSA` (PeerMSATests:160).
- **Duplicate sigla are accepted silently.** `collate run d1/X.txt d2/X.txt` runs, and the graph merges both witnesses' readings under `X`. A probe printed `["z": {"X"}, "b": {"X"}]`. Nothing validates sigla uniqueness and no test covers it.
- **The tokeniser silently drops non-BMP characters.** `Tokenizer.tokenize("the 𝔄 quick 𠀀 fox 😀", .diplomatic)` returns `["the","quick","fox"]`. The cause: Tokenizer.swift walks UTF-16 units and `UnicodeScalar(UInt16)` is nil for surrogates, so they hit the "safety: never stall" branch. As a result, a CJK Ext-B substitution (`𠀁`→`𠀂`) reports **0 variants**. This is a correctness bug, and no test or corpus case covers it.
- **Normaliser knobs.** Only the presets are tested. No test asserts accent folding (`café`/`cafe` gives no variant under substantive and a `variantSpelling` under `recordAccidentals`). `lowercase`, `dropPunctuation` and `splitHyphenatedWords` are never toggled one at a time.
- **No-collate syntax variants.** The explicit `<!-- /no_collate -->` close tag, the `no-collate` hyphen spelling, case-insensitivity and overlapping opens are all untested. Only the bare `-->` form is covered (TokenizerTests:112–146).
- **The `reusing:` perf seam** (`variantGraph(…reusing:)`) has a documented contract: results must equal the non-reusing build. It is only checked indirectly, by `CollateCLITests.testJSONExportEqualsConformanceGolden`, on one 2-witness case. I ran the release-path CLI (`collate run … --out`) against **every** corpus case it can express. All 26 matched their goldens byte for byte; 06, 07 and 16 need the `gbUS` normaliser, which has no CLI flag. So the contract holds today but is only asserted once.
- **`variantGraphWithTokens`** is reached only through the HTML exporter.
- **Line endings.** CRLF, CR-only and BOM handling has no direct test. CRLF works (same cites, offsets count `\r`). **CR-only input collapses to one line**: `line 2 · word 2` in LF becomes `line 1 · word 4`.
- **Unicode normalisation.** NFC vs NFD is untested. Under `--diplomatic`, NFC `café` vs NFD `café` gives 0 variants (Swift `String ==` is canonical-equivalence aware). This is behaviour a port must copy, and nothing pins it.
- **The HTML viewer JS** (~1,520 lines) has no CI check at all. `node --check` on the generated script passes today. The Playwright harness mentioned in TESTING.md is not in the repo.
- **No test compiles against the public API without `@testable`.** All 27 files use `@testable import`. At 1.0, a non-`@testable` `PublicAPITests.swift` is the cheap way to lock the API surface and catch accidental `internal` changes. The `collate-demo` and `collate-bench` builds give only partial cover.

---

## (B) Test-quality issues

### Tests that assert nothing (highest priority)

- **MoveRecoveryTests.swift:302–316 `testShortNearDiagonalMoveOnLongPairIsLikelyNotCertain`.** The assertion sits inside `for m in moves`, and on this input `moves` is empty. I confirmed with the CLI: `"transposition" : 0`. So the test asserts nothing, yet it takes **6.32 s, 68 % of the whole suite's runtime** (9.34 s). Either assert `!moves.isEmpty` with an input that actually produces the move, or delete it. Its sibling at :231 already pins the "no move" outcome.
- **PerformanceTests.swift:71–76 `testLongCollationIsDeterministic`.** It replaces `"ship600"`, which never occurs: word 600 is `the600`. So it collates two identical texts. Separately, `PerformanceTests:48–50` replaces `the300`, which also matches `the3000`, so the edit count differs from what the comment says (harmless only because the test asserts `> 0`).
- **MoveRecoveryTests.swift:57–69.** Same loop-only pattern: if `cat` ever stops being reported as a transposition, the test still passes. Today it does exercise one `likely` move.
- **PropertyTests.swift:259** asserts `count >= 0`. That is intentional ("completes without trapping"), but the comment should say so.

### Names or fixtures that no longer match what they check

- PropertyTests.swift:163 `testAppendedWordsAre…`: the words are inserted in the middle, not appended.
- TokenGraphTests.swift:25 `testSingleWordMoveIsOneTransposition` only asserts `contains { isMove }`, not "one".
- CollateCLITests.swift:58 `testBadLinesPerPageIsUsageError` never checks `.kind == .usage`.
- ConformanceTests.swift:136 `testCorpusIsNonEmpty` asserts `>= 15` against a corpus of 29. It would not notice a deleted case or an orphan golden. Assert the cases↔goldens bijection instead.
- TokenizerTests.swift:89–97: the comment says the rephrase is "reported as an insertion + a deletion". Since move recovery it is a transposition + 1 insertion, 0 deletions (MoveRecoveryTests:20–31). The assertion `ins+del > 0` still passes, but for a different reason.
- **Conformance case `05-transposition-internal-edit` is misnamed.** The edit (`heavy→oak`) is outside the moved span (`at last`), and its golden has `withinTransposition: false` everywhere. **No golden contains `withinTransposition: true`.**

### Implementation-detail and brittle assertions

- **Calibration constants restated as formulas.** These will churn on every recalibration, and memory shows two recalibrations already: MoveRecoveryTests:165–182 (re-derives `anchorMoveTolerance`), :349–357 (`moveTolerance == 3_000`), :366–404 (internal `pairByExpandingWindow` pairs), :282–300. Keep the data-backed population tests (:139–146, :184–211); they are acceptance bounds. Drop or merge the ones that only re-derive the formula.
- **Exact progress strings.** HTMLExportTests.swift:176–183 and :200–206 pin progress wording such as `"merging witness 1/1 onto the spine"` and `"  merging witness"` (indentation). This is UI copy, not contract. Assert stage order or structured progress events instead.
- **Positional menu scripts.** MenuTests.swift:51, 68, 97, 111, 123, 145 drive the menu with positional answers like `[dir, "", "", "", "", "", "", "", "1", "y"]`. Adding or reordering one prompt breaks all six. A small helper that answers by prompt substring would decouple them.
- **Exact label and prose copy.** CollationStrategyTests:31–35, ScoringPresetTests:38–42, NarrativeTests:30–41 (`"alignment is sound"`, `"substantive collation"`) and MenuTests:127 (`"LOCATED VARIANT REPORT"`). The `cite` format (`"p.1 · line 1 · word 3"`, LocationTests:33/44/90) is fine to pin: it is wire contract and appears in the goldens.

### Crash-instead-of-fail

Force unwraps and `try!` mean a regression kills the xctest process instead of failing one test:
- LocationTests:28–29, 39–40, 50–51, 60–61, 68, 87–90
- PaginationTests:21–23, 54
- RecursiveAnchoringTests:28, 33
- LiteraryEditionsTests:108, 124
- PeerMSATests:28, 34, 111, 118–119
- PunctuationTests:30–31
- CollationJSONTests:18, 23
- RenderingTests:80
- HTMLExportTests:63, 89 (`try! XCTUnwrap` in non-throwing tests)

Use `try XCTUnwrap`.

### Duplication and dead code

- **The `"the well-known author"` move** is pinned 4×: MoveRecoveryTests:20 and :107 (the second is a strict subset of the first), TokenizerTests:92, TokenGraphTests:25, plus golden 25.
- **CollationStrategyTests:80–90** repeat :61–70.
- **"Default argument == explicit default" tautologies:** CollationStrategyTests:52–57, ScoringPresetTests:30–36.
- **The six-edition texts exist in three copies:** LiteraryEditionsTests:18–81, `Samples.sixEditions`, and corpus case 16. That is a drift risk. Use `Samples` in the tests.
- **`CapturingSink`** is defined twice (CollateCLITests:16, HTMLExportTests:20), and an inline `Sink` twice more in MenuTests (:120, :132).
- **Dead lines:** HTMLExportTests:145 (`var run = makeRun(); _ = run`), CollateCLITests:129–130 (`_ = try? validate(o)` then a reassignment that does nothing), PropertyTests:117.

### Environment dependence and nondeterminism

- **Wall-clock thresholds.** PerformanceTests:55–62 (`< 1.0 s`, measured 0.20 s) and LexicalDiversityTests:40–44 (`< 3.0 s`, measured 0.23 s), both in debug. They pass with about 5× margin on an M-series Mac, but they can flake under coverage instrumentation, sanitizers or shared CI runners. Gate them behind an env var, or run them only in the release-test job.
- **Process cwd mutation.** DirectoryBrowserTests:83–85 calls `changeCurrentDirectoryPath`. That is safe today only because XCTest runs serially inside one process.
- **Leaked temp dirs.** HTMLExportTests:155, 168, 191 create directories and never remove them.
- **Corpus found via `#filePath`.** ConformanceTests:26, CollateCLITests:119 and PunctuationTests:76 locate the corpus this way. That breaks under path remapping (`-file-prefix-map`) or relocated test bundles. Acceptable, but worth a comment.
- **`COLLATION_RECORD=1` hazard** (ConformanceTests:37/147). If the variable is left set in a shell, the suite silently rewrites every golden and **passes**. Record mode should still `XCTFail("goldens re-recorded; re-run without COLLATION_RECORD")`, and CI should assert the variable is unset.
- **In-process determinism checks are weaker than they look.** Tests such as ConformanceTests:163, PropertyTests:75, LiteraryEditionsTests:172, GraphInsertionTests:82 and TokenGraphTests:59 compare `f(x) == f(x)` within one process. Swift's hash seed is fixed per process, so they **cannot** detect output that depends on `Set`/`Dictionary` iteration order. Only the cross-process golden comparison can. Run `ConformanceTests` in several separate processes in CI, which is cheap at 0.3 s each.
- **Locale and time zone.** None found. `normalize` uses a fixed `en_US` locale, `lowercased()` is locale-independent, and the manifest timestamp is passed as `nil` in tests.

### Slow tests (macOS debug, per test)

| test | time |
|---|---:|
| MoveRecovery…NearDiagonal…LikelyNotCertain | **6.32 s** (asserts nothing) |
| PropertyTests…LargeRepetitiveReorderedPairsDoNotTrap | 0.98 s |
| LexicalDiversity…PathologicalLowDiversity | 0.23 s |
| everything else | ≤ 0.2 s |

Suite totals: MoveRecovery 6.41 s, Property 1.45 s, LexicalDiversity 0.53 s, Performance 0.44 s, Conformance 0.31 s, the rest < 0.06 s each. Without the vacuous test the whole suite runs in about 3 s.

---

## (C) Conformance corpus gaps and schema strictness

**What it does well:** 29 cases, all 29 goldens validate, all are byte-reproduced on macOS **and on Linux (Swift 6.1 and 5.9.2)**, and they mix real and synthetic text across Latin, Greek and Cyrillic. As a *behaviour* contract it is good. As a *portability* contract it under-specifies exactly the places ports diverge.

### Behaviours with no golden

- **The `diplomatic` normaliser.** No case uses it (every case is `substantive` or `gbUS`), although README.md lists it, and the harness branch at ConformanceTests:100 is dead.
- **`withinTransposition: true`.** Case 05 does not do this (see B). Move-with-internal-edit, a headline feature, has no portable pin.
- **`no_collate` regions.** This is a documented input syntax with no case.
- **Page markers other than `<!-- page break -->`.** Form-feed (`\f`) and stand-alone `---` breaks are not covered; only `<!-- page break -->` (6×, all in case 16) is. `PaginationModel.explicit` cannot even be expressed in `meta.json`.
- **Scoring preset (`verse`) and non-default `anchorLength`.** `meta.json` has no field for either, so the verse preset cannot be ported verifiably.
- **Lexicon with base-anchored strategy.** Case 29 is the only lexicon case and it is peer-MSA.
- **Line endings, by accident only.** CRLF appears only incidentally: cases 17 and 26 are committed CRLF (`git ls-files --eol`: 4× `i/crlf`). **There is no `.gitattributes`**, so a Windows checkout with `core.autocrlf=true` rewrites the 63 LF witness files and the LF goldens, and the byte compare fails for the wrong reason. Add `docs/conformance/** -text`. Add explicit LF-vs-CRLF and CR-only cases.
- **NFD vs NFC.** Swift's canonical-equivalence equality yields 0 variants. A byte-comparing port will report substitutions and shifted `charTo`. This needs a case plus a sentence in ALGORITHMS.md §2/§9.
- **Non-BMP.** Currently these characters are silently dropped (bug, see A). Pin the fixed behaviour with a case (CJK Ext-B or mathematical letters). It also tests the UTF-16-offset claim for `charFrom/charTo` across surrogates.
- **Empty or whitespace-only witness, and a single witness (`pairs: []`).** Empty vs `the cat sat` gives 1 insertion via the CLI. The library `output(witnesses: [])` traps.
- **A very long single line, and a large input.** The biggest witness in the corpus is 1.2 KB. So none of the size-dependent §5.6 gates (`minMoveTokens` 200, `confidentMoveWitnessFloor` 4000, `fullNWCellCap` 1 M, banding, adaptive anchoring) is pinned for ports, and those are the most port-fragile calibrations. Add 1–2 deterministic synthetic cases of about 5k tokens (about 30 KB each).
- **`confidence: likely`.** It appears in only one golden (19), and `crossesPage: true` only in 16.

### Harness and metadata

- **`meta.base` is decoded but never used.** The harness takes `witnessOrder[0]`.
- **Unknown values default silently.** An unknown `normalizer` or `strategy` string becomes `substantive` / `base-anchored` (ConformanceTests:61–66, :97–103), so a typo silently changes what a case tests. Throw instead.
- **No schema for `meta.json`.**
- **The README overstates CLI coverage.** It says the options "map one-to-one onto … the CLI flags". The `gbUS` normaliser has no CLI flag, so cases 06, 07 and 16 cannot be reproduced with `collate`.

### Byte format left unspecified

Ports are told to match "byte-for-byte … sorted keys" (README; ALGORITHMS §8–9), but nothing documents Apple `JSONEncoder` pretty-print specifics:
- two-space indent
- `"key" : value` with a space on each side of the colon
- `/` escaped as `\/`
- non-ASCII written raw
- a trailing `\n` (added by the harness)

§9.5 says "sorted" without naming the ordering. Swift `String <` is Unicode-scalar order on canonical (NFC) form, which is neither UTF-16 order (JS, Java) nor locale order. Specify it, or ship a `canonicalize.py` that ports pipe their output through.

### `validate.py` robustness

- `open()` has no `encoding=` (validate.py:33, :43). On Windows (cp1252) the Greek, Cyrillic and French goldens fail to decode. File handles are never closed.
- It validates only `HERE/golden`. **A port cannot point it at its own output**: there is no path argument, despite README's "a port in any language can reuse … this script".
- It does not check cases↔goldens correspondence or `meta.json`, and does no semantic checks (sortedness, `counts` == tally of `variations`, `from <= to`).
- `jsonschema>=4.0` is unpinned.

### Schema strictness

`additionalProperties: false` is set on every object, enums are closed and `schemaVersion` is a `const`. Those parts are good. But I fed `Draft202012Validator` mutated copies of golden 02, and **14 invalid mutations were ACCEPTED**:
- `pairs: []`
- `graph.nodes: []`
- `readings: []`
- `witnesses: []`
- duplicate sigla in `witnesses`
- `baseID: ""`
- `RangeDTO` with `from > to`
- `charFrom > charTo`
- `cite: ""`
- `basePosition: -1` without `insertedAfter`
- `insertedAfter` on a normal node
- an insertion with all token ranges and locations nulled
- `counts` disagreeing with `variations`
- a non-transposition with `confidence: "likely"`

Only extra keys and a wrong `schemaVersion` were rejected. Expressible fixes:
- `minItems: 1` and `uniqueItems` on `witnesses`; `minItems: 1` on `readings`
- `minLength: 1` on `baseID`, `base`, `compared` and `cite`
- `if basePosition == -1 then required insertedAfter, else not insertedAfter`
- `if type != transposition then confidence const "certain"`
- per-type `if/then` rules on which token ranges are present

Also **drop the `{"type":"null"}` alternatives**. The encoder omits nil keys (no golden contains `null`), so a port that emits `null` passes the schema but fails the byte compare. The non-expressible invariants (ordering, `from <= to`, count tallies) belong in validate.py.

---

## (D) CI and platform recommendations

Current state: one macOS 15 job (`swift build`, `swift test`, `swift build -c release`) plus an Ubuntu Python schema job. **That is not sufficient for 1.0.**

1. **Add a Linux job. It is verified to work.**
   - In `swift:6.1-jammy` (aarch64), the library, CLI, demo and bench all build unchanged.
   - With `TestCountGuardTests.swift` removed, **all 221 remaining tests pass, including all 29 goldens byte-identical**, in 5.2 s. The same holds on Swift 5.9.2 (see 2).
   - The *only* Linux blocker is TestCountGuardTests.swift:33: `type 'XCTestSuite' has no member 'default'` (corelibs XCTest).
   - I found no Apple-only API in Sources. `NSRegularExpression`, `String.folding`, `CharacterSet`, `as NSString`, `NSHomeDirectory` and `ISO8601DateFormatter` are all available in corelibs or swift-foundation.
   - A Linux golden run is the cheapest real evidence for the "portable, deterministic" claim.
2. **Add a Swift-version matrix.**
   - Package.swift declares `swift-tools-version: 5.9`, but CI only uses whatever Xcode `macos-15` defaults to (unpinned, so it drifts).
   - Test the declared floor and the latest: Linux `swift:5.9` and `swift:6.x`. On macOS, pin Xcode explicitly, and consider `macos-14` with Xcode 15.4 (Swift 5.10) for the floor.
   - `platforms: [.macOS(.v13)]` is never executed on macOS 13. Acceptable, but say so in the README.
   - **Verified: `swift:5.9-jammy` (Swift 5.9.2, the pre-swift-foundation corelibs JSONEncoder) builds and passes all 221 tests, goldens byte-identical**, once the guard is removed. So the 5.9 floor is real today, but nothing in CI keeps it that way.
3. **Test in release mode.** CI builds release but never tests it. Either:
   - add `swift test -c release -Xswiftc -enable-testing` (also the right place for the wall-clock perf tests), or
   - at minimum, run the release `collate` over every corpus case and diff `collation.json` against the goldens. I did this locally and 26/26 CLI-expressible cases match. It is also the missing end-to-end CLI test.
4. **Make determinism and record mode explicit.**
   - Run `swift test --filter ConformanceTests` 3–5 times as separate processes, so randomised hash seeds get a chance to expose order leaks.
   - Fail the job if `COLLATION_RECORD` is set.
   - Run `git diff --exit-code docs/conformance` after tests.
5. **Check the viewer JS.** Extract the `<script>` from a generated `collation.html` and run `node --check` (passes today). Optionally add a Playwright/WebKit smoke test that loads the page with case 08 and checks for no console errors. That replaces the harness TESTING.md says lives outside the repo.
6. **Python job.**
   - Pin `jsonschema`.
   - Fix the `encoding="utf-8"` issue, or also run on `windows-latest`.
   - Add a `validate.py <dir>` mode and use it on a fresh CLI export, so the script is exercised the way a port would use it.
7. **Housekeeping.**
   - `timeout-minutes` on jobs.
   - Optionally `-Xswiftc -warnings-as-errors`, and a strict-concurrency or Swift 6 language-mode check before freezing a 1.0 API.
   - Caching `.build` is low value: there are no dependencies and a clean build plus test takes about 25 s. Skip it, or key it on the toolchain version.
   - A coverage report (llvm-cov export) is optional; the baseline is 92.6 % of lines.

---

## (E) TestCountGuard recommendation

**Remove it. Do not replace it with a blocking CI check.**

- **It breaks the Linux build of the test target.** `XCTestSuite.default` does not exist in swift-corelibs-xctest (verified, Swift 6.1). Linux CI is impossible while it exists.
- **It produces a guaranteed red `main` under normal contribution flow.** Two independent PRs that each add one test both change `documentedTestCount` 222→223. Git merges the identical one-line edits cleanly, both PRs are green, and merged `main` has 224 tests against a constant of 223.
- **It undercounts Swift Testing.** It counts XCTest leaves only, so any `@Test` a contributor writes is invisible to it. The Swift 6 toolchain already runs Swift Testing alongside XCTest (the log shows "Test run with 0 tests").
- **It taxes every PR.** Each test added or removed requires edits to four places: the constant, README, TESTING.md and DEVELOPMENT_LOG. That is pure friction for a number of little value to users.
- **Replacement:**
  - Stop quoting exact counts in prose ("200+ tests across 27 suites", or just the suite table).
  - If an exact number is wanted, regenerate it at release time with a script run from the release checklist (`swift test list | wc -l` works on macOS and Linux and includes Swift Testing).
  - At most, add a *non-blocking* CI annotation that prints the count.

---

## (F) Prioritised tests to add before 1.0

### P0: correctness bugs or contract holes found in this review

1. **Non-BMP tokenisation.** Assert that `𝔄`, `𠀀` and an emoji produce tokens. Assert that a CJK Ext-B substitution yields one substitution and that `charFrom/charTo` are correct UTF-16 offsets across surrogates. (Fix the tokeniser first.) Add a matching corpus case.
2. **Empty and degenerate inputs on every public entry point.**
   - `CollationJSON.output/outputString(witnesses: [])` (currently traps)
   - `variantGraph([])`
   - a single witness under `.baseAnchored`
   - an empty-text witness, and empty vs empty
   - corpus cases for an empty witness and a single witness
3. **Duplicate sigla.** Decide the contract (reject with `CLIError.witnesses` and a precondition or documented behaviour in the engine), then test it at both the CLI and library level.
4. **Fix the two tests that assert nothing:**
   - MoveRecoveryTests:302: assert `!moves.isEmpty`, or delete it and save 6 s.
   - PerformanceTests:73: use a token that exists, e.g. `the600`, and assert a variant appears.
5. **CLI↔golden parity over every case.** Parameterise `testJSONExportEqualsConformanceGolden` over all CLI-expressible cases (26 match today), or add a `--normalizer gbus` flag so all 29 qualify. This is what enforces the `reusing:` and `output(graph:pairs:)` contracts.
6. **Corpus case for `withinTransposition: true`.** Fix or rename case 05 and add a true move-with-internal-edit.

### P1: portability contract

7. **More corpus cases:**
   - `diplomatic` normaliser
   - `no_collate` (single-comment form and `<!-- /no_collate -->` form)
   - form-feed and `---` page breaks
   - CRLF vs LF and CR-only
   - NFC vs NFD
   - one deterministic ~5k-token pair that exercises the §5.6 gates and banding
8. **Add `.gitattributes`** (`docs/conformance/** -text`), plus a test asserting that the CRLF witness files still contain `\r`, so normalisation by an editor or git is caught.
9. **Tighten the schema.**
   - Add the `minItems`/`uniqueItems`/`minLength`/`if-then` rules from (C) and drop the `null` alternatives.
   - Add semantic checks to validate.py: sortedness, `counts` tally, `from <= to`, cases↔goldens bijection, UTF-8 `open`, and a `[dir]` argument.
   - Add schema-negative tests: a few invalid fixtures that must be rejected.
10. **Make meta parsing strict.** Unknown `normalizer`/`strategy` should throw, and `base` must equal `witnessOrder[0]`. Add a `meta.schema.json`, and add `scoring` (and optionally `anchorLength`) fields so the verse preset can be ported.
11. **Add `PublicAPITests.swift` without `@testable`.** Exercise each public entry point and DTO field, to freeze the 1.0 surface.

### P2: coverage and robustness

12. **CLI paths:**
    - `list --dir`
    - `--lexicon` (missing file gives `.io`, empty file gives `.usage`, a valid file changes output)
    - `--lines-per-page 3` success
    - `--through-numbered`, `--accidentals` and `--record-punctuation` end to end
    - WitnessLoader errors (not a directory, unknown `--order`/`--base` siglum, non-UTF-8 file)
13. **Normaliser unit tests:** accent folding (substantive gives no variant, `recordAccidentals` gives `variantSpelling`), plus each `Normalizer` flag toggled on its own. Also `CollationNarrative` with recorded accidentals (l.100) and a ≥3-kind summary (l.199).
14. **Reach the uncovered branches, or delete them:**
    - `legacyVariantGraph`
    - `Alignment.banded` delete-edge and `maxBand` cap
    - `Transposition` degenerate window
    - the PeerMSA l.175/l.368 paths
    - `ApparatusEntry ==`
    - `CollationJSON.string(graph)`
15. **Viewer smoke check in CI:** `node --check` on the emitted script, and optionally a headless load of one export.
16. **Hygiene, no new behaviour:**
    - replace force unwraps with `XCTUnwrap`
    - share a single `CapturingSink`
    - make menu scripts prompt-keyed
    - clean up temp dirs in HTMLExportTests
    - move wall-clock assertions to the release job
    - make `COLLATION_RECORD` fail loudly
