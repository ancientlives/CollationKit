# `collate` — full interactive CLI app (BACKLOG B9) — plan

The prototype `collate-demo` is a one-shot preview harness. **B9** promotes it into a full, friendly
command-line **harness for the CollationKit engine** — **`collate`** — a convenient way to fully exercise,
test, and demonstrate the engine on real witness files: collate a set of files from a local directory, view
results in the console, and export them for use elsewhere, via both an **interactive menu** and a
**scriptable flag** mode. It sits alongside the unit tests and the benchmark harness as another way to *drive*
the engine — the engine itself stays the primary work (see §0).

This document is the plan: scope, architecture, the interactive flow, output/export formats, the docs and
tests to ship with it, and a phased build order. It is written to be self-contained, so B9 can be
implemented from it directly. TEI I/O is explicitly **out of scope** (split to backlog **B12**).

**Status:** this is the design plan. The shipped flags are those listed by `collate --help`; `CLI_GUIDE.md` has
not been written.

---

## 0. Layering — the CLI is a HARNESS for the engine kernel, not a product built on a finished one

**What this CLI is *for*.** `collate` is a **convenient, friendly way to fully exercise, test, and demonstrate
the CollationKit engine** — a front door for running real collations, trying options, and inspecting/exporting
results by hand. It is a *harness around the work*, in the same family as `CollationKitTests` and
`collate-bench`: another way to drive the engine. It is **not** a downstream product that "consumes" a
finished library, **not** a replacement for the engine, and **not** where the project's value lives.

**The engine is the primary work and keeps developing.** `CollationKit` is, and must remain, a **standalone,
dependency-free, pure-Swift kernel** — the same library the unit tests, the conformance corpus, the benchmark
harness, and any future UI front end drive (the engine was originally prototyped as the collation engine for a
native macOS markdown editor). The backlog is mostly *engine* work
(B6c, B10, B11, …); building this CLI must **not** slow that down, fork it, or freeze it. As the engine grows,
the CLI simply exposes the new capability — it rides along, it doesn't gate.

```
                         ┌──────────────────────────────────────────────┐
                         │  CollationKit  (the engine KERNEL — library)  │   ← THE PRIMARY WORK,
                         │  pure value types · no AppKit · no I/O · det. │      still developing
                         │  public API: Collation, CollationJSON,        │      (B6c, B10, B11, …)
                         │  Report, Apparatus, Synopsis, Tokenizer, …    │
                         └──────────────────────────────────────────────┘
                              ▲              ▲               ▲          ▲
       drive/exercise the     │              │               │          │   a future
       engine (harnesses) ────┤              │               │          └──── consumer
        ┌─────────────────────┴──┐   ┌───────┴────────┐  ┌───┴───────┐  ┌──────────────┐
        │ CollationKitTests       │   │ collate-bench  │  │  collate  │  │  future UI   │
        │ (unit + conformance)    │   │ (benchmarks)   │  │  (B9 CLI) │  │  front end   │
        └─────────────────────────┘   └────────────────┘  └───────────┘  └──────────────┘
              ▲ harness            ▲ harness         ▲ harness (this item)   ▲ future work
```

`collate` belongs to the **harness** column with the tests and the benchmark — tools that *drive* the engine
so it can be developed, verified, and shown working. A UI front end (future work) would be a *consumer* of the
engine rather than a harness. The CLI's job is to make the kernel easy to run and inspect; the kernel's job is to
be correct, fast, and embeddable in any host.

**Two phases, deliberately sequenced.** Right now the CLI is a **proof of concept** to *build out incrementally
as a way to test the engine* — value comes from exercising new engine capability quickly, not from CLI polish.
Treat it as a growing test harness: add just enough CLI to drive each engine feature, keep it correct and
deterministic, but **don't gold-plate the UX yet**. Only once **CollationKit itself reaches v1.0 / "finished"**
do we **polish `collate` for release usage** (hardened UX, packaging, distribution, full help/man pages,
broader format support). Until then, engine progress is the scoreboard; the CLI rides along. The phased order
in §9 reflects this — early phases are "enough to drive and inspect," release polish is explicitly last and
gated on engine maturity.

**Rules this plan holds itself to (so the kernel stays clean, reusable, and unblocked):**

1. **No engine logic in the CLI.** `CollateCLI`/`collate` contain *only* I/O, argument parsing, file
   discovery, formatting/export, and the interactive menu. Anything algorithmic — tokenisation,
   normalisation, alignment, classification, the variant graph, the JSON shape — lives in `CollationKit` and
   is reached through its **public API**. If the CLI ever needs something the engine doesn't expose, the fix
   is to add/clean a small public surface on the engine (benefiting tests and any other consumer too), **not** to
   reimplement it in the CLI.
2. **The engine never depends on the CLI.** Dependency arrows point one way: `collate` → `CollateCLI` →
   `CollationKit`. The engine has no knowledge of, and no dependency on, the CLI; removing `collate` must
   leave the engine and its tests untouched.
3. **Same kernel, every harness.** The CLI drives the *same* `Collation.collate` / `variantGraph` /
   `CollationJSON.outputString` the tests assert on and any embedding application would call. That is what makes a
   CLI run, a conformance golden, and an embedded collation byte-for-byte comparable — and is precisely why the CLI is a
   *good way to exercise the engine*: what you see in the CLI is what the tests pin and any embedding gets. It also
   keeps the CLI honest as the engine evolves (a CLI export and a golden are the same artifact).
4. **Embeddability preserved.** `CollationKit` stays AppKit-free, I/O-free, and dependency-free so it lifts
   into a native Swift application with zero FFI/serialisation boundary (its founding constraint). All the
   *terminal* concerns — reading files, prompting, writing exports, `exit` codes — are confined to the CLI
   targets and never touch the kernel.
5. **The CLI follows the engine, never gates it.** Engine development sets the pace; the CLI exposes whatever
   the engine can do at any point. A half-built engine feature is simply not surfaced yet — the CLI never
   forces an engine change to suit itself, and engine work proceeds whether or not the CLI is built.

In short: **the CLI is a harness that makes the engine easy to run, test, and show — not a product layered on
a finished engine.** Where this plan says "the engine," it means the existing, still-developing library; where
it adds code, it adds it in the CLI layer unless a deliberate, documented engine improvement is called for (in
which case it lands in `CollationKit` with its own tests, for everyone — the tests, this CLI, any embedding).

---

## 1. Goals & non-goals

**Goals**
- Make it **easy to fully exercise and test the engine by hand** on **real shared files** (a chosen local
  directory of witnesses), not just the built-in sample — a friendly front door to the same functionality the
  tests pin.
- An **interactive menu** for users who don't want to remember flags: pick a directory, pick/order
  witnesses, choose options, run, view, export.
- A **non-interactive flag mode** for scripting/CI (everything the menu does, via flags + a `--no-input`
  switch), and **stdin** input for piping.
- **Output to console** (the existing located report / apparatus / synopsis) **and export to files** in
  several formats (text, JSON, CSV) into a chosen output directory.
- Friendly, robust UX: clear errors, `--help`, confirmation before overwriting, sensible defaults.

**Non-goals (this item)**
- TEI input/output (→ **B12**); HTML export (→ **B8**); a GUI/TUI with full-screen panes (a native viewer is
  separate future work). The menu here is a simple **prompt-driven**
  REPL, not an ncurses TUI.
- **Any change to the engine's algorithms or any engine logic living in the CLI** (see §0). The CLI is a
  *thin* I/O + UX layer over the existing `CollationKit` public API (`Collation`, `CollationJSON`, `Report`,
  `Apparatus`, `Synopsis`). The engine remains a separate, still-evolving kernel shared with the tests and the
  other harnesses; this item adds a *harness* that drives it, it does not absorb or fork the kernel.

---

## 2. Architecture

A new executable target **`collate`** plus a small, **testable command-core library** so the logic is unit-
tested without driving a terminal.

```
Package.swift
  + .executable(name: "collate", targets: ["collate"])
  + .target(name: "CollateCLI")                         # the testable core (no process/exit, no raw stdin)
  + .executableTarget(name: "collate", deps: [CollateCLI])  # the thin main: wire argv + real IO to the core
  + test target gains CollateCLITests

Sources/
  CollationKit/                ← THE ENGINE KERNEL — unchanged by this item; consumed, never modified here
  CollateCLI/                  ← CLI core — pure, testable; **depends on CollationKit only** (one-way arrow)
    CLIOptions.swift           — parsed run configuration (a value type); flag parsing + validation
    WitnessLoader.swift        — discover .txt/.md files in a directory; load → [Witness]; ordering; base pick
    OutputFormat.swift         — enum { text, json, csv } + which sections (report/apparatus/synopsis)
    Exporter.swift             — render a CollationRun → String per format; write files to an output dir
    CollationRunner.swift      — orchestrates: options → load → collate → render (the one place that calls the engine)
    Menu.swift                 — the interactive flow as a STATE MACHINE over an abstract IO protocol
    ConsoleIO.swift            — `protocol ConsoleIO { func prompt(_:)->String; func print(_:) }` (mockable)
  collate/
    main.swift                 — parse argv, build CLIOptions, run interactive Menu or one-shot Runner; map exit codes
```

**Why a separate `CollateCLI` target:** the interactive menu and the exporters are the parts most worth
testing, and they must be tested **without** a real TTY. `Menu` is written against a `ConsoleIO` protocol; a
`ScriptedConsoleIO` (a queued list of answers) drives it in tests. `main.swift` stays a tiny adapter. This
mirrors the project's existing "pure core, thin shell" stance and **keeps the layering of §0 enforced by the
build graph**: `collate` → `CollateCLI` → `CollationKit`, never the reverse. `CollationKit` builds, tests, and
embeds in an application with or without these CLI targets present — they are additive harnesses, not part of
the kernel.

**No third-party dependencies.** Hand-rolled arg parsing keeps the zero-dependency stance (consistent with
the rest of the package); the surface is small enough that `swift-argument-parser` is not worth a dependency,
but the plan notes it as an option if the flag set grows.

---

## 3. Invocation modes

```sh
# Interactive (no args, or just --dir): launches the menu.
collate
collate --dir ./witnesses              # start the menu pointed at a directory

# One-shot, explicit (scriptable; non-interactive):
collate run A.txt B.txt C.txt                          # collate these files (first = base)
collate run --dir ./witnesses --all                    # collate every witness file in the directory
collate run --dir ./ed --base MS --order MS,TS,PR      # choose base + witness order explicitly
collate --no-input run --dir ./ed --all --format json --out ./results   # fully scripted, never prompts

# Piping / stdin:
cat a.txt | collate run --stdin-base - other.txt       # base from stdin
collate run --dir ./ed --all --format json | jq .      # JSON to a pipe

collate --help            # usage; collate run --help  → run-mode flags
collate --version
```

**Subcommands (kept minimal):** `run` (collate), and the default (no subcommand) → interactive menu.
`list` (show the witness files discovered in a directory) is a convenient extra.

---

## 4. Options (flag mode == menu choices; one model, `CLIOptions`)

| flag | menu prompt | meaning | default |
|------|-------------|---------|---------|
| `--dir <path>` | "Witness directory?" | folder to discover witnesses in | `.` |
| `--all` / select | "Which witnesses?" | use all discovered files, or a chosen subset | all |
| `--base <id>` | "Base witness?" | the copy-text (graph base) | first in order |
| `--order <a,b,…>` | "Order the witnesses" | collation order (and successive-pair order) | directory sort |
| `--substantive` / `--diplomatic` | "Comparison mode?" | normalizer + overlays preset | substantive |
| `--accidentals` | "Report spelling/case accidentals?" | `recordAccidentals` | off |
| `--record-punctuation` | "Report punctuation (diplomatic)?" | `recordPunctuation` | off |
| `--gb-us` | "Fold GB/US spelling?" | use the GB↔US spelling table | off |
| `--lines-per-page N` / `--through-numbered` | "Pagination model?" | `PaginationModel` | source markers |
| `--sections report,apparatus,synopsis` | "What to show?" | which output sections | all |
| `--format text\|json\|csv` | "Output format?" | console + export encoding | text |
| `--out <dir>` | "Export to a folder? (blank = console only)" | write results to files | none (console) |
| `--no-input` | — | never prompt; fail if a required choice is missing (for CI) | off |
| `--quiet` / `--verbose` | — | console verbosity | normal |

`CLIOptions` validates (e.g. base must be among the witnesses; `≥2` witnesses; output dir writable) and
returns clear errors. The **`--diplomatic` preset** sets `recordPunctuation` + `recordAccidentals` on and uses
the `.diplomatic` normalizer; `--substantive` is the default scholarly view.

---

## 5. The interactive menu (flow)

A prompt-driven state machine. Every prompt shows the current default in `[brackets]`; empty input accepts it.
`?` re-shows help for the step; `b` goes back; `q` quits.

```
$ collate

  CollationKit · interactive collation
  ════════════════════════════════════

  1) Witness directory  [./witnesses]  ▸  (enter a path, or ↵ to accept)
     › ./editions

     Found 4 witness files:
       [1] MS.txt        (1,204 words)
       [2] TS.txt        (1,198 words)
       [3] PR.txt        (1,210 words)
       [4] GB1.txt       (1,209 words)

  2) Which witnesses?  [all]  ▸  (e.g. "1,2,4" or "all")
     › all

  3) Base (copy-text)?  [MS]  ▸
     › ↵

  4) Order?  [MS,TS,PR,GB1]  ▸  (comma list, or ↵)
     › ↵

  5) Comparison mode?  [1]
       [1] Substantive (default — fold accidentals)
       [2] Diplomatic  (also report spelling + punctuation)
     › 2

  6) Pagination?  [1]
       [1] Source markers   [2] N lines/page   [3] Through-numbered
     › 1

  7) Output sections?  [all]   (report, apparatus, synopsis)
     › ↵

  8) Format?  [text]   ([1] text  [2] json  [3] csv)
     › 1

  9) Export to a folder?  [console only]  ▸  (path, or ↵ for console)
     › ./results

  ── Summary ─────────────────────────────────────────────────
   4 witnesses · base MS · diplomatic · source pages · text → ./results
  Run? [Y/n]  › ↵

  … collating …

  ✓ Wrote:
     ./results/located-report.txt
     ./results/apparatus.txt
     ./results/synopsis.txt
     ./results/collation.json        (always also emits the machine-readable interchange)
  (printed a summary to the console; full report in the files above)

  [r]un again · [e]dit options · [q]uit  › 
```

Edge cases the menu handles: directory with `<2` witnesses (explain, offer to pick another), unreadable
file (warn + skip, like the demo does today), output dir exists with files (confirm before overwrite),
non-UTF-8 file (clear error).

**Shipped refinement (2026-07-07) — the directory steps are a visual browser, not a bare path prompt.** The
sketch above shows step 1 / the export step as "enter a path". As built, both use `DirectoryBrowser`
(`DirectoryBrowser.swift`), redesigned the same day after the first cut proved clumsy (it hid the
files, its "empty line selects" was invisible, and it mis-used `.` for "up"). Each view shows the current path,
then a **unified listing**: the current folder's **subfolders numbered** (`<n>` opens one) followed by the
**witness files** already present (with sizes — informational, so you can see what you'd collate). A persistent
action line spells out every command: `u` (or Enter) **USE this folder**, `..` up (Unix `..`, not `.`),
`<n>` open, type a path, `q` cancel. It starts at the current working directory (so a globally-installed
`collate` behaves like any CLI — begins where you are; `--dir` overrides). The witness step requires the target
to exist and only lets you USE a folder with ≥2 witness files (the action line's label reflects the count, and
trying to use an under-populated folder warns and keeps browsing rather than bouncing out). The export step is a
Yes/No first, then — on Yes — the same browser with `purpose: .output` and *require-existing off*, so a
not-yet-created output folder name typed at the prompt is accepted (the exporter creates it). Pure over the
`ConsoleIO` seam, so `DirectoryBrowserTests` drives it with no terminal. Back-navigation history (`b`) and the
`?` per-step help in the sketch remain Stage-B refinements.

---

## 6. Output & export

**Console** — the existing renderers: `Report.located` (per successive pair), `Apparatus.plainText`
(N-witness apparatus criticus), `Synopsis.plainText` (parallel columns). *(Updated 2026-07-07:)* the console
text view is **capped** (`Exporter.consolePreview`, 2 000 lines) with an explicit truncation notice pointing
at `--out` — a full-novel report is millions of characters and an uncapped dump reads as a hang. Every run
reports **per-stage progress to stderr** (witnesses loaded → each pair → the graph → rendering) and ends with
an explicit `✓ collation finished` line (counts + elapsed time); stdout stays clean for piped output.

**Export files** (into `--out <dir>`), by format:

- **text**: `located-report.txt`, `apparatus.txt`, `synopsis.txt` — the console renderings, file-per-section
  (always complete — the console cap is presentation only).
- **json**: `collation.json` — the existing `CollationJSON` interchange (`{graph, pairs}`). This is *always*
  written alongside any format, so a run is reproducible/consumable downstream (it is the same artifact the
  conformance corpus pins).
- **csv**: `variants.csv` — one row per variant for spreadsheet/data use:
  `pair_base,pair_compared,type,confidence,base_reading,compared_reading,base_cite,compared_cite,crosses_page`.
  A new tiny `Exporter` function (CSV is trivial to emit deterministically; quote per RFC 4180).
- **html** *(B8, shipped 2026-07-07)*: `collation.html` — the **interactive collation viewer**, ALSO always
  written on export (and available as `--format html` to stdout): a self-contained page with perspective tabs
  per witness, alignment highlights by variation type, a filterable variant panel with cross-perspective
  hops, and the N-witness apparatus view. See `HTMLExport.swift` and DEVELOPMENT_LOG 2026-07-07.

A `manifest.txt` (or `run.json`) records the run configuration (witnesses, options, engine/schema version,
timestamp) so an exported result set is self-describing — the same self-describing ethos as the benchmark
harness header.

All exports are **deterministic** (sorted/stable, matching the engine's determinism rules), so they can be
snapshot-tested and diffed.

---

## 7. Docs to ship

- **`README.md`** — add a "Run the CLI" section (interactive + scripted examples) and a one-line pointer.
- **`docs/development/CLI_GUIDE.md`** (new) — the user guide: every option, the menu walkthrough, the export
  formats with a sample of each, scripting/CI recipes, troubleshooting. Cross-linked from `docs/INDEX.md`.
- **`docs/INDEX.md`** — add the `collate` tool + `CLI_GUIDE.md` rows.
- **`DEVELOPMENT_LOG.md`** — a dated entry (`usage`): why the CLI, the testable-core design, the formats.
- **`reference/PAPER_NOTES.md`** (and the engine paper, in preparation) — a sentence in the implementation/availability
  section: the engine ships with a usable CLI (helps the "integration-ready" contribution and a reproducible
  artifact for reviewers).
- `collate --help` / `collate run --help` text is itself a doc surface; keep it complete and tested.

---

## 8. Tests (the reason for the `CollateCLI` core)

A new `CollateCLITests` suite — all without a real terminal:

- **Option parsing & validation** — flags → `CLIOptions`; bad input (missing base, `<2` witnesses,
  unwritable out dir, unknown format) → clear errors; `--diplomatic` preset sets the right engine flags.
- **Witness discovery** — a temp directory of `.txt`/`.md` files → correct `[Witness]`, ordering, base
  selection; non-text skipped; deterministic order.
- **Exporters** — golden strings for text/json/csv from a known witness set; CSV quoting/escaping; the JSON
  export equals `CollationJSON.outputString` (reuse the existing contract); determinism (same bytes twice).
- **Interactive menu** — drive `Menu` with a `ScriptedConsoleIO` (a queued answer list) through several
  paths: accept-all-defaults; choose a subset + base + order; diplomatic mode; export vs console-only;
  back/quit; the `<2`-witnesses and overwrite-confirm branches. Assert the resulting `CLIOptions` and the
  files "written" (to an in-memory/temp FS).
- **End-to-end (one-shot)** — `collate run --dir fixtures --all --format json --out tmp` produces the
  expected files; the JSON matches a conformance golden for that witness set (ties the CLI to the corpus).
- **`--help`/`--version`** — present, non-empty, mention every flag (a cheap guard against drift).

Target: keep the suite fast and deterministic (temp dirs cleaned up; scripted IO; fixed sample witnesses).

---

## 9. Phased build order

**Stage A — proof-of-concept harness (now; build out incrementally as the engine grows).** Enough CLI to
drive and inspect the engine; correct and deterministic, but *not* gold-plated.

1. **Core + one-shot `run`** (no menu yet): `CLIOptions`, `WitnessLoader`, `CollationRunner`, console text
   output, `--out` text+json export. Wire `collate run …`. Tests for parsing/loading/export.
2. **CSV exporter + `manifest`** + `list` subcommand. Tests.
3. **Interactive `Menu`** over `ConsoleIO` + `ScriptedConsoleIO`; the full flow in §5; `--no-input` guard.
   Menu tests.
4. **Docs** (`CLI_GUIDE.md`, README section, INDEX rows) + `--help` text + the DEVELOPMENT_LOG entry.

Each Stage-A phase is independently usable and testable; phase 1 already gives a scriptable tool, with the
interactive menu (the headline of B9) landing in phase 3. As new *engine* features land (B6c, B10, …), expose
them here with a flag/menu option and a test — that is the harness doing its job.

**Stage B — release polish (LATER; gated on `CollationKit` reaching v1.0 / "finished").** Do **not** start
this until the engine is stable enough to ship. Then: hardened UX, friendly error catalogue + exit codes
(0 ok · 1 usage · 2 no/!witnesses · 3 IO), `--quiet/--verbose`, overwrite confirmation, packaging &
distribution (a installable binary, completions, a man page), and any broader format/UX work a *release* tool
needs. Until the engine is done, keep this list parked — engine progress is the priority, not CLI shine.

> Keep `collate-demo` as-is (it's referenced by docs and is a minimal example); `collate` is the growing
> harness. Once the engine hits v1.0 and `collate` is polished (Stage B), `collate-demo`'s docs can point at
> `collate` for real use.
