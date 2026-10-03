# CollationKit CLI + HTML viewer review (October 2026, at e340719)

Scope: `Sources/CollateCLI/*`, `Sources/{collate,collate-demo,collate-bench}/main.swift`, `Package.swift`,
`site/build-demos.sh`; intended behaviour from `CLI_PLAN.md` and `VIEWER_UX_PLAN.md`.
Method: release and debug builds in a scratch build path. I ran a matrix of about 40 CLI invocations. The
interactive menu was driven through **piped stdin** (`TerminalConsoleIO` reads `Swift.readLine`, so no TTY is
needed). I ran one full-novel export with `/usr/bin/time -l`. Viewers were loaded in Playwright WebKit (plus
Chromium for comparison) with console and page-error capture, clicking every tab and timing interactions. The
repository was not modified.

---

## (A) Confirmed bugs

### A1. HIGH — Viewer: a witness containing `<!--<script` blanks the whole page (silent)
- `Sources/CollateCLI/HTMLExport.swift:266`. The only transform on the embedded JSON is `</` → `<\/`. `<` is
  not escaped.
- Repro: a witness containing `… a sneaky <!--<script> opener …` (no `-->` after it), then
  `collate run --format html A.txt B.txt > esc.html`, then open it.
- Observed: the HTML tokenizer enters the "script data double-escaped" state, so the template's own
  `</script>` no longer closes the data block. The rest of the document, including the viewer script, is
  swallowed into `#data`. In WebKit: 0 tabs, `document.scripts.length == 1`, a blank page and **no console
  error**.
- Expected: a working viewer for any input text.
- Fix: escape `<`, `>` and `&` as `<`, `>` and `&` in the JSON. That is the standard
  JSON-in-HTML approach and also makes the `</` replace redundant.
- Gap: `HTMLExportTests.testHTMLIsSelfContainedEscapedAndDeterministic` only tests `</script>`.
- Plain `</script>`, backticks, `${…}`, quotes and `&` in the text are all handled correctly (verified).

### A2. MEDIUM — Viewer: HTML injection through witness ids (filenames)
A witness id is the filename stem, and several `innerHTML` sinks leave it unescaped:
- `HTMLExport.swift:1231`: `primaryMate` in the Overview "What kind of change?" callout.
- `:2035`: `capitalise(mate)` in the Story tab.
- `:2118`: `D.base` in the Alignment verdict.

Repro: `cp A.txt '<img src=x onerror=window.__pwnedId=1>.txt'; cp B.txt '<i>zz<i>.txt'`, then
`collate run --format html --dir . --all`, then open the page. `window.__pwnedId === 1` fires on load (Overview
is the landing tab).

Related, also confirmed:
- `HTMLExport.swift:267-269`. `%%TITLE%%` is substituted before `%%DATA%%`, so a witness named `%%DATA%%.txt`
  gets the whole unescaped JSON payload pasted into `<title>`/`<h1>`.
- `:2154`, `:2157` double-escape. `esc()` output is assigned to `textContent`, so the axis labels of id
  `A&B` render literally as `A&amp;B →`.

Severity: the pages are published on the website (`site/demos`) and shared as files, so this is
script-in-a-file.

### A3. HIGH (Safari/WebKit) — Viewer: "changes ✎" tab freezes for about 1 minute on a full novel
- `HTMLExport.swift:541`: `#changes .sub-old {… opacity:.75}`, applied to about 25.8k spans.
- Repro: the full *Mysterious Island* export below. Click Overview, then "changes ✎".
  - WebKit: **55.6 s** (repeat run 60.2 s). Leaving the tab while it is painted is also slow: changes→story
    took **117 s**, because the spinner frames repaint the heavy view underneath.
  - With an injected `#changes .sub-old,#changes .del{opacity:1}`, the same transition takes **0.97 s**.
  - Chromium: 0.74 s.
- Expected: about 1 s. Fix: use a lighter colour instead of `opacity`.
- The same pattern exists, at lower volume, in `.likelySpan` (`:341`) and `#list .likely` (`:327`).
- The earlier `VIEWER_UX_PLAN` perf notes are Chromium-agnostic and miss this; Safari is the primary macOS
  browser.

### A4. MEDIUM — CLI: duplicate witness ids are accepted silently, which corrupts the viewer and reports
- `WitnessLoader.swift:63-83`. There is no uniqueness check on sigla.
- Repros:
  - `collate run e1818/text.txt e1831/text.txt`, a very natural layout (one folder per edition). Both ids are
    `text`, so you get "text differs from text…" and `pairs: [(text,text)]`.
  - `collate run A.txt A.txt`, or `--order A,A`, gives exit 0 with "0 variants".
  - `run --dir two two/A.txt` collates A twice (3 witnesses).
- Viewer (`dup.html`):
  - Two tabs both labelled `text (base)`.
  - `textById` (`:719`) keeps the last text, so the base tab shows the *compared* text under base offsets.
  - The parallel, changes and story witness selectors are empty.
- Expected: a usage error ("witness id 'text' is ambiguous; rename files, or let the loader disambiguate by
  parent dir"), and reject duplicates in `--order`.

### A5. MEDIUM — Menu: the confirm prompt runs on "no" and on EOF
- `Menu.swift:39-42` uses `ask` (EOF becomes the default "y") and `default: return .run`.
- Repro: `printf 'u\n\n\n\n\n\n\n\nno\n' | collate --dir two` collates (exit 0, "✓ collation finished").
- The same happens if stdin ends right at the confirm prompt.
- This contradicts the header comment ("EOF … treated as quit") and CLI_PLAN §5.
- Expected: only `y`/empty runs; `n`/`no` edits; EOF quits.

### A6. MEDIUM — Menu: base siglum is not validated; a typo is only caught after confirm, and exits
- `Menu.swift:84-85`.
- Repro: `printf 'u\nall\nBB\n…' | collate --dir two`.
  - The summary shows "base BB".
  - After confirm: `error: --base 'BB' is not among the witnesses`, exit 2, and the menu is gone.
- The same applies to step 4 (`orderList`, `:88-90`), which is never validated.
- Expected: re-ask at the prompt.

### A7. LOW-MEDIUM — Menu: "edit options" does not carry answers forward
- `Menu.swift:79-101`. The witness subset, base and pagination always reset to "all / first / 1".
- Repro: choose `1,3` and 50 lines/page, then `n`. The second summary reads "all witnesses · … · source pages".
- The comment at `:28-29` claims "the last answers as defaults".

### A8. MEDIUM — CLI: the output directory is checked only after the whole collation
- `CollateCLI.swift:127-135`: `Exporter.write` runs after `CollationRunner.run`.
- Repro: `chmod 555 ro2; collate run --out ro2 A B` does all the work, then
  `error: cannot write ro2/located-report.txt`, exit 3.
- On the full novel this throws away about 12 s of collation and HTML render (minutes in a debug build).
- CLI_PLAN §4 says validation covers "output dir writable". Pre-flight it (create the dir and test a write)
  before collating.

### A9. LOW-MEDIUM — CLI: the documented `--no-input` forms do not work
- `CollateCLI.swift:34,45,60-61`. `--no-input` is recognised only in the bare/`--dir` form.
- `collate --no-input run …`, the exact CI recipe in CLI_PLAN §3, fails with `unknown command '--no-input'`,
  exit 1.
- `collate run --no-input …` fails with `unknown flag`. The help text says "--no-input also forbids the menu"
  without saying where it goes.

### A10. LOW — CLI: no per-command help
- `collate run --help` gives `error: unknown flag '--help'`, exit 1. CLI_PLAN §3 and §7 promise
  `collate run --help`.
- `collate help` is an unknown command, which dumps the full usage to stderr with exit 1.

### A11. LOW — CLI: a bare `collate` with a non-TTY stdin silently does nothing, exit 0
- Repro: `collate < /dev/null` prints the menu, reads EOF, prints "(quit — nothing collated)", exit 0.
- A mis-wired CI step therefore "passes". Also:
  - `collate --dir` with no value launches the menu instead of erroring (`:60` skips 2).
  - `collate --dir /nonexistent` silently starts in the cwd (`DirectoryBrowser.normalizedExistingDir`).
- Expected: when `!isatty(0)`, refuse the menu with a usage error.

### A12. LOW — CLI: misleading I/O error text
- `WitnessLoader.swift:101`. An unreadable file (`chmod 000`), a directory passed as a witness
  (`run two A.txt`), `-` (stdin, CLI_PLAN §3) and Latin-1 bytes all report `cannot read (or not UTF-8): …`.
- Distinguish "permission denied", "is a directory", "not UTF-8 (byte offset N; try iconv)", and
  "stdin not supported".

### A13. LOW — Viewer: Overview and graph copy are wrong for N > 2 witnesses
- `HTMLExport.swift:1231`. Run-wide totals are attributed to the first non-base witness.
  - Six-editions: "Across the whole work, **TS differs from MS at 14 points**", but TS has 1 (tab badge `TS 1`).
  - The confidence card underneath measures only that one witness ("1 shared points", also a plural error).
- Graph header (`:1359`) with peer-msa (`tri.html`): "28 variant points across 85 aligned positions", while
  the same tab's badge says 88 variant nodes.
  - The text tabs and summary come from *base-anchored pairwise* annotations; the graph is the *peer MSA*.
  - Two different alignments are shown without explanation.

### A14. LOW — Viewer: "checked — none found" is asserted for a type that was never checked
- `HTMLExport.swift:1235` and the `0 · checked` bars. In a substantive run, spelling/case are *folded* by the
  normaliser, not checked.
- Repro: "The Sea was calm, and grey." vs "the sea was calm and grey!"
  - Substantive: "textually identical".
  - Diplomatic: 4 points.
- The Overview still says "Spelling/accidental differences were checked and none were recorded".
- The same claim is in the `CollationNarrative` text, which is engine-side.

### A15. LOW — `collate-bench --csv` reports success on failure
- `collate-bench/main.swift:217-218` uses `try?` and then unconditionally prints `wrote CSV to …`.
- Repro: `collate-bench --quick --csv /nonexistent/dir/x.csv` prints "wrote CSV to /nonexistent/dir/x.csv",
  exit 0.

### A16. LOW — `collate-demo` falls back to the built-in sample, and claims JSON identity with `collate`
- `collate-demo/main.swift:47`. `collate-demo A.txt` (one file) or `--bogus A B` silently prints the built-in
  six-edition sample.
- `:41`. Ids include the extension (`A.txt`), so `collate-demo --json A B` is *not* byte-identical to
  `collate run --format json A B` (`baseID "A.txt"` vs `"A"`). This contradicts `Exporter.swift:83-84` and
  `CollationJSON.swift:126-129`.

---

## (B) Suspected issues (code-read or partially measured)

- **B1. Quadratic text slicing.**
  - Where: `renderText` (`HTMLExport.swift:867`) and `sliceInto` (`:1798`) run `rows.filter(…)` per segment,
    which is O(segments × annotations): about 60k × 31.7k comparisons on the full novel.
  - Measured: base tab 3.3–4.3 s and witness tab 6.0 s (WebKit), parallel 6.6–8.6 s.
  - VIEWER_UX_PLAN recorded parallel at about 3.4 s, so this looks like a regression on a bigger corpus.
  - Fix: a sweep with an active set makes it O(n log n).
- **B2. Every render rebuilds the hidden list.**
  - `render()` (`:2219`) calls `renderList()`, which rebuilds all 31,750 rows.
  - This happens on every tab switch, even when `#side` is hidden.
  - Hidden views also keep their DOM: total nodes grow to 350–420k and WebContent RSS reaches 1.13 GB after
    visiting all tabs. Clear inactive views.
- **B3. Fast-path selection is not fast.**
  - Span click: 1.13 s synchronous handler (from `scrollIntoView` plus layout).
  - A "hop" row click: 5.1 s. Filter toggle: 1.7 s.
- **B4. Graph scroll redraws every move edge.**
  - `drawMoves` iterates every edge, about 195k, on every scroll frame. Graph scroll frames measured at
    about 66 ms, i.e. 15 fps.
  - Keep a pre-filtered move-edge list.
- **B5. Parallel linked scroll is expensive.**
  - `firstVisiblePV` calls `getBoundingClientRect` on every `.pv` in the column for each scroll event.
  - Measured handler time: 23–36 ms per event, which janks on trackpad scroll.
- **B6. The base perspective list does not say which witness a row belongs to.**
  - The six-edition base list shows "tired → weary" five times, once per witness, with no siglum (see the
    mobile screenshot).
- **B7. Stale files survive a re-export.**
  - Re-exporting into an existing `--out` never removes files from a previous run with another format, e.g.
    `variants.csv`. `manifest.txt` then describes a different set of files.
  - No overwrite confirmation (CLI_PLAN Stage B).
- **B8. `CollationRunner.run` traps on short input.**
  - It traps for `witnesses.count == 0` (`1..<0`), and for count 1 with `includeViewerPairs` (`pairs[0]`).
  - It is public API; only the loader's ≥2 guard protects it.
- **B9. Inconsistent exit codes.**
  - `--base X --order Y` mismatch gives 1 (usage), while `--base Z` with no such witness gives 2.
  - Both are "unknown base".
- **B10. Last-wins flags.** Contradictory flags silently take the last value: `--diplomatic --substantive`,
  `--lines-per-page N --through-numbered`. `--all` is a no-op (the directory default is already "all").
- **B11. Narrative wording oddities** (engine side, surfaced by the CLI):
  - "3 of these are reported as possible moves…, the rest as certain" when the rest is 0.
  - In diplomatic mode, "4 points … In all: 2 substitutions (50%) and 1 deletion" doesn't add up.
- **B12. `site/build-demos.sh:27-32`.** No `trap` for the `mktemp` lexicon file, so a failed peer run leaves
  it behind. Minor.
- **B13. The exporter tokenises the base 3×, plus once per witness.**
  - In `payload`, `graphDTO` and `summaryDTO`.
  - The full HTML (about 70 MB) is built as one String and copied by two `replacingOccurrences` passes and
    `+ "\n"`.
  - This contributes to the 7.5 s HTML stage and the 1.3 GB peak RSS.

---

## (C) Redundant or deprecatable code and targets

- **`collate-demo` is functionally a subset of `collate`.**
  - Its unique features: printing the full witness texts, and the built-in `Samples.sixEditions` with the
    GB/US normaliser. It has weaker parsing (A16).
  - Docs reference it in README:47, ONBOARDING:70/227, conformance README:65 and `ConformanceTests.swift:125`
    (comments).
  - Recommendation: deprecate.
    - Add `collate demo` (or `collate run --sample six-editions`) for the zero-argument showcase.
    - Point the docs at `collate`.
    - Keep `collate-demo` one release as a shim that prints a deprecation notice, then drop the product from
      `Package.swift`.
    - Fix the "byte-identical to `collate-demo --json`" comments to name `collate run --format json` /
      `CollationJSON.outputString`.
- **`collate-bench` is still useful but narrow.**
  - Useful: a deterministic synthetic sweep of length × diversity × N and the two strategies. Recorded run
    (`--quick`) is sane. It is the only cost-scaling evidence for the paper (BENCHMARKS.md).
  - Gaps:
    - No real-corpus point, although the 21.8 s full-novel run shows that graph finalisation (8.5 s) and HTML
      export (7.5 s) dominate.
    - Its graph timing calls `variantGraph` without `reusing:`, so it measures a path the CLI no longer takes.
    - Unknown flags are ignored, and A15.
  - Keep it. Add an optional `--corpus a.txt b.txt` point that times the stages the CLI actually runs, fix
    A15, and run `--quick` in CI as a smoke test.
- **Library surface.** `ScriptedConsoleIO` (a test double) is `public` in the shipping `CollateCLI` library.
  It could move to the test target via `@testable`.
- **`--all`** is a no-op flag; keep it as an alias, but say so in `--help`.

---

## (D) Viewer: function, performance and accessibility

**Functional (WebKit; every tab clicked; 0 console errors and 0 page errors on all benign inputs).**
- six-editions (143 KB), trilingual peer + lexicon (179 KB) and the A&B/esc2 fixtures: all 9–13 tabs render
  non-empty views. Tab switches take 80–140 ms.
- The published `site/demos/six-editions.html` and `verne-trilingual.html` are byte-identical to fresh
  output, so the site demos are current.
- Broken cases are A1 (blank page), A2 (injection), A4 (duplicate ids) and A13/A14 (wrong copy).
- Peer-msa graph: sigla chips are truncated ("EN-MERCIEF") and readings are ellipsised in the column nodes;
  the full text is only visible on hover or click.

**Performance — full novel** (*Mysterious Island* kingston × white, 1.11M + 0.95M chars; WebKit, 1400×900):

| step | time |
|---|---|
| CLI run (release) | **18.9 s wall, max RSS 1.32 GB** (peak footprint 954 MB) |
| ↳ stage split | pair 1.3 s · graph merge 1.0 s · **graph finalise 8.5 s** · text files 1.2 s · json 2.2 s · **html 7.5 s** |
| outputs | **collation.html 69.8 MB** (graph 47 MB, apparatus 16 MB, annotations 9 MB, texts 2 MB) · collation.json 93 MB |
| page load to interactive (Overview) | **0.6–1.1 s** |
| base text tab / witness tab | 3.3–4.3 s / 6.0 s |
| variant graph tab / scroll frame | 0.6–4.7 s / ~66 ms |
| apparatus (capped at 4000) | 0.17–0.23 s |
| parallel ⇄ | 6.6–8.6 s (RSS → 1.08 GB) |
| **changes ✎** | **55.6–60.2 s** (A3; 0.97 s with the opacity fix; Chromium 0.74 s) |
| story (after changes) | **117 s** (0.24–0.29 s otherwise) |
| alignment / overview | 0.24 s / 0.07 s |
| span click / hop click / filter toggle | 1.1 s / 5.1 s / 1.7 s |

The graph payload (47 MB, 67% of the file) carries every agreement node and spine edge. Run-length-encoding
agreement runs, or omitting implicit spine edges, would roughly halve the file.

**Accessibility.**
- **Keyboard.** Only the tab `<button>`s and the filter checkboxes are focusable (tested in Chromium; WebKit's
  default Tab skips buttons). None of these are keyboard-reachable: variant spans, list rows, Overview nav
  cards, histogram bars, graph nodes, minimap, apparatus lines, change chunks, story examples, alignment dots.
  They are all `div`/`span` with `onclick` and no `tabindex`, role or key handler. The core exploration is
  mouse-only.
- **Semantics.** There are no ARIA attributes at all (0 `[role]`, `[aria-*]`, `[tabindex]`).
  - Tabs lack `role=tablist/tab` and `aria-selected`; the active tab is visual only.
  - The witness `<select>`s (parallel, changes, story, alignment) have no label.
  - The spinner has no `aria-busy` or live region.
  - Alignment-map dots expose information only through hover tooltips.
- **Colour-only encoding.** Variation type in the text is background plus underline colour only (amber, green,
  red, blue, purple). The legend teaches it, but there is no non-colour cue on the span. Amber, green and red
  are hard to tell apart under deuteranopia. The minimap, histogram and graph stripes are colour-only too.
- **Contrast (WCAG).**
  - Graph position numbers `#c4c0bb` on white: **1.81:1**.
  - Apparatus position `#a8a29e`: **2.52:1**.
  - Legend separator `#d6d3d1`: 1.49:1.
  - `opacity:.65/.75` "likely" labels drop below 3:1.
  - Body text, tab and type labels are 4.8–10:1, which passes.
- **Layout.**
  - `main{height:calc(100vh - 118px)}` assumes a one-row tab bar. With wrapped tabs (6 witnesses, or a narrow
    window) the panes overflow.
  - At 390 px width the text column is about 50 px wide, because `#side` has `min-width:320px` (screenshot
    `shots/six-mobile.png`).
  - No dark-mode styles.

---

## (E) CLI UX improvements (in priority order)

1. Pre-flight validation before collating:
   - unique sigla (A4)
   - `--out` writable (A8)
   - witness files readable, with a specific reason (A12)
   - warn on empty witness files (currently a silent 0/1-variant result)
2. Accept `--no-input` anywhere. Add `collate run --help`, and refuse the menu when stdin is not a TTY
   (A9–A11).
3. Menu:
   - Validate base and order at the prompt (A6).
   - Strict y/n/EOF at confirm (A5).
   - Carry the selection forward on edit (A7).
   - Expose `--strategy`, `--scoring` and `--lexicon` (today the menu cannot produce a peer-msa or lexicon
     run, despite "one config, two front doors").
   - Say why when an invalid numbered choice falls back to the default.
4. Reject contradictory flags (`--diplomatic --substantive`, two pagination modes) instead of last-wins. Make
   the unknown-base exit code consistent (B9).
5. Implement or remove the plan-only flags (`--stdin`/`-`, `--quiet`/`--verbose`, `--sections`, `--gb-us`).
   CLI_PLAN still presents them as the design.
6. Progress: the graph "finalising" stage is 40% of a full-novel run with no sub-progress. Also add a
   per-file size line to `wrote:` (a 70 MB HTML file surprises people).
7. Export:
   - Clear or namespace stale outputs (B7).
   - Offer `--no-viewer` / `--no-json` so a CSV-only scripted run doesn't write 160 MB.
   - Print the `open …` hint on stdout or make it quieter.
8. Documentation: `CLI_GUIDE.md` (CLI_PLAN §7) is still unwritten; `--help` is the only reference.

---

## (F) Release-readiness verdict

- **CLI (`collate`): almost ready for a "harness / preview" release; not ready as a polished 1.0 tool.**
  - Good:
    - The scripted `run` path is solid: clean stdout/stderr separation (piped JSON parses), sensible exit
      codes 0/1/2/3, clear messages for most errors.
    - Deterministic exports, and the full novel runs in 19 s / 1.3 GB.
  - Must fix before release: A4 (duplicate ids), A5/A6 (the menu runs on "no" or a typo'd base), A8 (late
    out-dir failure).
  - Should fix: A9/A10 (documented `--no-input` and `run --help`).
  - The rest are polish.
- **Viewer (`collation.html`): not ready to ship.**
  - It works well on small and medium collations, with zero JS errors across all tabs.
  - A1 (a blank page from ordinary-looking text) and A2 (script injection through file names) are
    correctness and security defects in a file meant to be shared and published.
  - A3 makes the Changes tab unusable in Safari on full-length works.
  - Accessibility is mouse-only, with no ARIA, colour-only type encoding and several contrast failures.
  - The minimum to ship: A1, A2 and A3, all small fixes. Then B1/B2 for full-novel responsiveness, then a
    keyboard/ARIA pass.
