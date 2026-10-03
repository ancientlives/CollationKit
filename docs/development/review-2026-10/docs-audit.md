# CollationKit documentation audit (release 1)

Repository: CollationKit, branch `review/release-1` at `e340719`. Read-only audit, 3 October 2026.

**Scope.** I read every Markdown file at the root, under `docs/` (except the case and golden fixtures),
`corpus/verne/*.md` and `.github/`, plus the text of `site/index.html`. I also compared the maintainer's
pre-release working copy file by file (see F). `docs/development/review-2026-10/` appeared while this audit was
running. It is outside this audit.

**How the facts were checked.**
- Test count: `grep 'func test'` gives 222. There are 27 `XCTestCase` classes, and
  `TestCountGuardTests.documentedTestCount` is 222.
- Cases: `ls docs/conformance/cases` gives 29, with 29 goldens. Two cases are strategy-pinned: 28 and 29.
- Schema: the `const` is 3.
- Views: `HTMLExport.swift:766-789` defines 8 tabs.
- Export files: `Exporter.swift:157-171` writes 7 files for `--format text`.
- Parameters: the values in `Transposition.swift`, `PeerMSA.swift` and `Alignment.swift` were compared with
  the tables in `ALGORITHMS §10` and `PAPER_NOTES §9`. All of them match.
- Full-novel runs used `.build/release/collate` (built from the current sources on 25 September) on the three
  pairs that do not need Walter. `collate-bench --quick` was run once.

---

## (A) Classification

| Document | Class | Reason |
|---|---|---|
| `README.md` | UPDATE (minor) | The counts are correct. The pipeline table leaves out `CollationNarrative.swift`. The Walter exception does not cover the published demo. The "limits" pointer points at the wrong section (see B). |
| `CONTRIBUTING.md` | CORE | Accurate: workflow, invariants and golden discipline (`COLLATION_RECORD=1` checked in `ConformanceTests.swift:37`). It should gain a "landing a behaviour change" section taken from TOKEN_GRAPH_PLAN §4, and a CHANGELOG step. |
| `CODE_OF_CONDUCT.md` | UPDATE (minor) | Contributor Covenant 2.1. Its only reporting route is "a minimal public issue". A private contact is needed. |
| `LICENSE-docs.md` | UPDATE | The Walter exception names cases 20/22/29 and the goldens. It does not name `site/demos/verne-trilingual.html`, which embeds the same 87-word paragraph and is published on GitHub Pages. |
| `CITATION.cff` | UPDATE | Says `version: "0.1.0"`, but there is no git tag, and the CLI reports `0.2.0`. |
| `.github/PULL_REQUEST_TEMPLATE.md` | CORE | Accurate. Add a CHANGELOG checkbox once a CHANGELOG exists. |
| `.github/ISSUE_TEMPLATE/*` (`bug_report`, `collation_result`, `feature_or_research`, `config`) | CORE | Accurate, and the links resolve. There is no route for questions or support, because blank issues are disabled. |
| `.github/CODEOWNERS` | CORE | Fine. |
| `docs/INDEX.md` | UPDATE | Lists three shipped plans as current design docs. Overstates the test-count guard (B). It has to be rewritten for whatever structure is chosen in (C). |
| `docs/RESEARCH_INTRO.md` | CORE | Accurate, and it is the right owner of "research directions". It has no hyperlinks at all. Its §4 is almost a paragraph-for-paragraph copy of ONBOARDING §6. |
| `docs/ONBOARDING.md` | UPDATE | 486 lines. §6 (about 140 lines) duplicates RESEARCH_INTRO §4, and §7 duplicates INDEX. Contains a misleading `contextualDefault` claim, the guard claim, and a "backlog item" that is not in the backlog. |
| `docs/conformance/README.md` | CORE | Verified: 29 cases, 9 real, 28/29 pinned to `peer-msa`, schema v3, and the test names it cites exist. |
| `docs/development/TESTING.md` | CORE | Verified: 222 tests and 27 suites, and the suite table matches the 27 classes. |
| `docs/development/BACKLOG.md` | UPDATE | B6 is marked in progress (◐) but its CJK strand has not started. B13 Step 2 is outside this repo. It leaves out the Part II items from the survey and release work (triage in E). |
| `docs/development/BENCHMARKS.md` | UPDATE | The recorded tables and `results.csv` date from 2026-06-30, before B11 and B14. Says "six export files" (there are seven). Describes the graph as a "progressive base-anchored fold". |
| `docs/development/CASE_STUDY.md` | UPDATE | The case write-ups are good. The "Implications" section and the scope note still present B10/B11 as open (B). |
| `docs/development/DEVELOPMENT_LOG.md` | CORE as a historical record, needs navigation | 2,266 lines, 58 dated entries, and no table of contents. The "at a glance" summary is frozen at 2026-07-24, and the log ends at 2026-07-24b, so the public release is not recorded (C). |
| `docs/development/CLI_PLAN.md` | ARCHIVE | Stage A shipped 2026-07-01. The plan's flag set and file list differ from what shipped (B). Its own status line says the user guide (`CLI_GUIDE.md`) was never written. §0 (layering) is still useful as architecture. About 20 source comments cite `CLI_PLAN §0/§6/§9`. |
| `docs/development/TOKEN_GRAPH_PLAN.md` | ARCHIVE | Its status line says done on 2026-07-02. Line 3 still reads "The next major engine update". ONBOARDING sends people to it for the migration discipline, which should move into CONTRIBUTING. |
| `docs/development/VIEWER_UX_PLAN.md` | ARCHIVE | Titled "UX roadmap", but all items shipped (2026-07-07 to 07-13c). It is a changelog of viewer iterations. Its "Constraints" section (lines 170-179) is still normative and belongs in a viewer guide or CONTRIBUTING. |
| `docs/development/CORPUS_PLAN.md` | FUTURE | Clearly marked "design / proposal (not built)". Move it to `docs/proposals/`. |
| `docs/porting/RUST_STANDALONE_PLAN.md` | FUTURE (also stale) | Self-described "planning experiment". Its "what to reuse" list (lines 61-68) predates the token graph, peer MSA, lexicon, scoring presets and the three false-move gates. M1 targets one six-edition golden rather than the 29-case corpus. |
| `docs/reference/ALGORITHMS.md` | CORE | The normative port spec. The §10 parameters match the code exactly, and §9 matches the tie-breaks. |
| `docs/reference/PAPER_NOTES.md` | CORE, with updates | The design rationale and bibliography. It has stale rows in §10 and stale text in §5.4. §5.3 keeps a 5-step build plan that has already been carried out. Its §9 parameter table duplicates ALGORITHMS §10, and §5.3/5.4 overlap COMPARISON. The name is paper-centric for a public repo. |
| `docs/reference/ALGORITHM_SURVEY.md` | CORE (minor update) | Accurate, and its references check out. It has two clashing numbering schemes, and test counts are hard-coded in 4 places the guard does not cover. |
| `docs/reference/COMPARISON.md` | UPDATE | Still says "validated on crafted + modest-scale tests", "three renderers" and "the UI defaults intelligently". |
| `corpus/verne/README.md` | UPDATE | The alignment and timing figures predate the move gates (B). The rest (layout, recipe, Walter provenance) is accurate. |
| `corpus/verne/BIBLIOGRAPHY.md` | CORE | A working bibliography under a strict verified-or-flagged rule. Its open flags are honest (the French *Tour du monde* ID, `moonvoyage` "Linklater?"). One stale figure: ~21.8k. |
| `corpus/verne/known-issues/README.md` | CORE (trim) | Its only issue is FIXED. Keep it as the template for new findings, but mark the "Likely area" and "Workaround" paragraphs (lines 31-40) as historical and fix the numbers. |
| `site/index.html` | UPDATE (minor) | The text is accurate, and the example output was reproduced exactly from `cases/16-six-editions` (`collate run MS.txt UNI.txt`). Two problems: "100–200k words per witness", and the `collate …` commands assume an installed binary that no doc explains how to install. Its 11 GitHub doc links must be updated if any doc moves. |

---

## (B) Stale facts to fix

Format: file:line. Current text, then the correct value or fix.

**Counts and claims**
- `docs/INDEX.md:108-109` and `docs/ONBOARDING.md:247-248`
  - Current: "build-enforced: `TestCountGuardTests` fails if the advertised count drifts" / "fails if the README's advertised figure drifts".
  - Fix: the guard compares discovery against **its own constant** (`TestCountGuardTests.swift:28`). It never reads README or TESTING, so prose can drift without failing the build. The literal 222 also appears in places its failure message does not list: `ONBOARDING.md:53,69,153,224,277` and `ALGORITHM_SURVEY.md:16,600,794,820`. Reword to "fails when the test count changes; its message lists the docs to update". Better still, remove the hard-coded counts from ONBOARDING and SURVEY and point at TESTING.md.
- `docs/ONBOARDING.md:198`
  - Current: "`CollationStrategy.contextualDefault(hasCopyText:)` picks between them."
  - Fix: nothing calls it except tests (`grep` finds it only at `Collation.swift:65`). The CLI default is fixed at `.baseAnchored` (`CLIOptions.swift:61`), and the interactive menu offers no strategy prompt. Reword to "the engine provides a context-aware default helper; the CLI defaults to base-anchored; pass `--strategy peer-msa`".
- `docs/ONBOARDING.md:274-278`
  - Current: "Pick a small backlog item … Fenwick-tree weighted LIS".
  - Fix: Fenwick is not in BACKLOG.md. It is only in ALGORITHM_SURVEY Part II item 1. Add it to the backlog or reword.
- `docs/ONBOARDING.md:405-410` (and `RESEARCH_INTRO.md:145-148`)
  - Current: "B13 Step 2 … an open backlog item".
  - Fix: the UI it targets is outside this repo (BACKLOG:21-24). Point it at the in-repo version instead: the interactive menu's missing strategy prompt.
- `docs/ONBOARDING.md:98-104` and `site/index.html` "Get started"
  - Current: bare `collate run …` commands.
  - Fix: no doc explains how to put `collate` on PATH. Either use `.build/release/collate` consistently or add install steps.
- `README.md:105-118`
  - Current: the pipeline table has no `CollationNarrative.swift` (a public engine render model that produces `summary.txt` and the Story tab) and no `Samples.swift`.
  - Fix: add both rows. ONBOARDING:180 already lists `CollationNarrative`.
- `README.md:156`
  - Current: "open fronts are summarised in RESEARCH_INTRO §4".
  - Fix: §4 covers research directions only. B6 (CJK) and B12 (TEI) are not there. Point at BACKLOG or a limitations page.
- `README.md:186-188` and `LICENSE-docs.md:21-27`
  - Current: the Walter text appears only "in three test cases".
  - Fix: it is also embedded in `site/demos/verne-trilingual.html` (built by `site/build-demos.sh:29-31` from case 29). Verified: the opening of `en-walter.txt` is present in the demo page.
- The source of the "limitation" in the private README
  - Current: missing from the release README.
  - Fix: "readings are re-joined with single spaces (original spacing and punctuation are not preserved in readings)" is still true (`Variation.swift:435-436, 517`). Only `ALGORITHM_SURVEY:573` mentions it. Add it to the README limits.

**Versioning**
- `CITATION.cff:10-11`
  - Current: `version: "0.1.0"`, `date-released: "2026-09-25"`.
  - Fix: there are no git tags (`git tag` is empty), and `collate --version` prints `0.2.0 (Stage A — engine harness, interactive)` (`Sources/CollateCLI/CollateCLI.swift:20`). Pick one version, tag it, and make the CLI, CITATION and CHANGELOG agree. The `--help` banner (`CollateCLI.swift:194`) also still says "BACKLOG B9, Stage A".
- `collate --help` (`CollateCLI.swift:219-220, 227`)
  - Current: `--format html` is described as "(perspective tabs, alignment highlights, variant panel)", and `--out` as "(collation.json + manifest always written)".
  - Fix: the viewer now has 8 views, and `--out` always writes `summary.txt`, `collation.json`, `collation.html` and `manifest.txt`. This is a documentation surface in code.

**Benchmarks**
- `docs/development/BENCHMARKS.md:77-108` and `benchmarks/results.csv`
  - Current: recorded in a single commit (`5da491c`). The CSV has no `strategy` column, so it was produced before B14.
  - Fix: the harness now emits `kind,…,witnesses,strategy,…` (`collate-bench/main.swift:211`), so the tables predate B11, B14 and the move gates. The doc admits this at line 22 ("Re-record the full CSV at the next B3 refresh"). The figures have moved: today's `--quick` gives 2000 words at diversity 0.80 = 8.94 ms (recorded 2000/0.90 = 6.09 ms), and N=4 × 1000 words = 19.6 ms base-anchored vs 13.4 ms peer (doc line 18 says ~16 vs ~10). Re-run the full sweep and replace both the tables and the CSV.
- `BENCHMARKS.md:43-44`
  - Current: "write all six export files".
  - Fix: **seven** for `--format text` (`located-report`, `apparatus`, `synopsis`, `summary`, `collation.json`, `collation.html`, `manifest`; see `Exporter.swift:159-171`).
- `BENCHMARKS.md:66, 121-122`
  - Current: "progressive base-anchored fold".
  - Fix: the token-graph lift since B11 (2026-07-02). The old fold survives only as `legacyVariantGraph`.
- `BENCHMARKS.md:48` vs `corpus/verne/README.md:37` vs `known-issues/README.md:10`
  - Current: the 20,000 Leagues full pair is quoted as ~5 s, ~9 s and ~3 s.
  - Fix: pick one number from a current measurement. This could not be re-measured here because Walter is not in the checkout.

**Verne corpus figures** (measured now with the release binary)
- `corpus/verne/README.md:38`, earth-to-moon
  - Current: "~7.4k variants, ~2 s; align 9.4% / 98.3%".
  - Now: 7,324 variants, 2.7 s, **3.3% drift / 100% monotonic**.
- `corpus/verne/README.md:39`, journey-centre-earth
  - Current: "~12.8k, ~4.5 s; align 12% / 98.6%".
  - Now: 12,755 variants, 5.3 s, **12% / 100%**.
- `corpus/verne/README.md:40`, mysterious-island
  - Current: "~31.8k, ~15 s; align 4.9% / 98.0%".
  - Now: 31,750 variants, 16.3 s, **2.9% / 100%**.
  - The improvement in monotonicity matches the false moves removed in July.
- The 20,000 Leagues figures cannot be verified here: `README.md:37` "~21.5k … 4.8% / 98.9%", `BIBLIOGRAPHY.md:81` "~21.8k", `known-issues/README.md:10` "≈21.8k", and `PAPER_NOTES.md:735-737` "18,074 shared points, 4.8%, 98.9%".
  - These were measured before the 07-15/16/24 gates; LOG:1920 counted 224 moves at the time. Re-measure after running `build_corpus.sh` and use one figure everywhere.
- `site/index.html:149`
  - Current: "Complete novels (100–200k words per witness)".
  - Fix: `wc -w` gives 40k to 193k (earth-to-moon 40k/51k, journey 74k/86k, mercier 105k, mysterious 193k/165k).

**Resolved items still framed as open**
- `docs/development/CASE_STUDY.md:36`, `:491-495` (implication 3), `:559-565` (scope note b)
  - Current: "cross-language collation needs translation-aware anchoring".
  - Fix: resolved by B10 + B14 (case 29). Add the same "Resolved" note that §Case 6 (line 342) already carries.
- `CASE_STUDY.md:502-503`
  - Current: "the fuller token-graph merge (B11), which remains the complete fix".
  - Fix: B11 shipped 2026-07-02.
- `CASE_STUDY.md:516-517`
  - Current: "The uniform fix … is the token-graph redesign, backlog B11".
  - Fix: done.
- `CASE_STUDY.md:563-564`
  - Current: "the remaining generalisation is the full token-graph merge (B11)".
  - Fix: done.
- `CASE_STUDY.md:488`
  - Current: "Greek (earlier)".
  - Fix: there is no Greek case study. Greek is conformance case 14 only. Say so.
- `docs/reference/PAPER_NOTES.md:797`
  - Current: the table row "positional alignment — limit of base-anchoring across languages".
  - Fix: add "→ resolved by B10/B14, case 29". §11 (line 826) already says resolved.
- `PAPER_NOTES.md:801-805`
  - Current: the headline says "bounded that generality (cross-language collation needs translation-aware anchoring …)".
  - Fix: same resolution.
- `PAPER_NOTES.md:615-618`
  - Current: "Don't gold-plate before the second strategy is real".
  - Fix: the second strategy has been real since B14. Delete this, or make it historical.
- `PAPER_NOTES.md:534-556`
  - Current: §5.3 steps 1-5 are written as an instruction to the implementer ("Replace the … loop …").
  - Fix: done. Move them to the archive, or collapse them into a past-tense paragraph.
- `PAPER_NOTES.md:819`
  - Current: "At the last review the suite was 222 tests (2026‑07‑24)".
  - Fix: still 222. Drop the date, or point at TESTING.md.
- `PAPER_NOTES.md:935` (references)
  - Current: "P. Robinson, 'Collation, textual criticism, publication, and the computer' (1989)".
  - Fix: probably *Text* 7 (1994), 77–94. **Verify.** The doc already flags its bibliography as not copy-edited. The other citations checked out (NW, SW, Hirschberg, Myers, Greg, Gotoh, Gale–Church, Ukkonen, Saitou–Nei, Fenwick).
- `docs/reference/COMPARISON.md:148`
  - Current: "a prototype validated on crafted + modest-scale tests".
  - Fix: validated on four full-novel translation pairs (40k–195k words), 9 real cases and a 29-case corpus.
- `COMPARISON.md:152`
  - Current: "a JSON interchange and three renderers".
  - Fix: JSON, CSV, text apparatus/synopsis/report, narrative, and the 8-view HTML viewer. TEI is still missing.
- `COMPARISON.md:131-133`
  - Current: "The UI defaults intelligently by context".
  - Fix: no UI does this. The CLI default is fixed at base-anchored. Make it conditional ("a UI should default…").
- `COMPARISON.md:101`
  - Current: "one of 26 conformance goldens changed".
  - Fix: historically correct, but it reads as current (there are 29 now). Add "(of the 26 at the time)".
- `docs/development/TOKEN_GRAPH_PLAN.md:3`
  - Current: "The next major engine update".
  - Fix: archive banner. Line 110's "(130 tests)" is historical.
- `docs/development/VIEWER_UX_PLAN.md:1-7`
  - Current: "UX roadmap … Five items were raised".
  - Fix: archive banner. It is a record of 8 shipped views.
- `docs/development/CLI_PLAN.md:172-179, 189-204, 265-270, 321`
  - Current: the plan lists `--no-input run`, `--stdin-base`, `--gb-us`, `--sections`, `--quiet/--verbose` and a 4-file export.
  - Fix: none of those flags shipped. `--strategy`, `--scoring` and `--lexicon` shipped but are not in the plan. The export now always writes `summary.txt`, `collation.html` and `manifest.txt`. This is why it is an archive and not a guide.
- `docs/porting/RUST_STANDALONE_PLAN.md:61-68, 117-118`
  - Current: the reuse list and "six-edition JSON matches".
  - Fix: add the gates, token graph, peer MSA, lexicon and scoring presets, and set M1 to all 29 goldens plus `validate.py`.
- `docs/development/BACKLOG.md:10`
  - Current: B6 is ◐.
  - Fix: the CJK strand is not started (☐). The other strands are in the done ledger.
- `docs/development/DEVELOPMENT_LOG.md:20`
  - Current: "Resolved-vs-open at a glance (as of 2026-07-24)".
  - Fix: the log ends at 07-24b. The public release (2026-09-25), the website and the 2026-09-06 verification are not logged.
- `DEVELOPMENT_LOG.md` State lines
  - The suite count goes 26 at `:2227` → 27 at `:2264` with "+2 MoveRecoveryTests" and no new suite. The earlier "26 suites" lines undercounted, since `TestCountGuardTests` has existed since 07-01. Add a one-line erratum rather than rewriting history.
- `docs/reference/ALGORITHM_SURVEY.md:29-52, 589-806`
  - Part I's table numbers algorithms 1–20 but the sections are §1–18. Part II numbers items 1–16, and Part III cites them by those bare numbers. Prefix them (A1…A20, C1…C16).

**Accurate, no change needed:** `TESTING.md` (counts and suite table), `conformance/README.md`, `ALGORITHMS §9-10`, `PAPER_NOTES §9` values, README test and suite counts, the "eight views" (INDEX:31/73, README:94, ONBOARDING:395), the site example output, and all relative Markdown links. No links are broken; the two false positives are placeholders (`pgNNN.txt`, `collation.html` in a title).

---

## (C) Duplication and a proposed structure

**Duplication found**

| Topic | Where it is written | Proposed single owner |
|---|---|---|
| "Why not diff" | README §Why, ONBOARDING §1, RESEARCH_INTRO §1, site | README (short) and RESEARCH_INTRO (long). ONBOARDING links to them. |
| Research directions (ML, UI/UX, the intersection) | RESEARCH_INTRO §4 and ONBOARDING §6 (about 140 lines, same arguments in the same order) | RESEARCH_INTRO. ONBOARDING §6 becomes about 15 lines: where each direction sits in the code and the backlog. |
| Vocabulary | RESEARCH_INTRO §3, ONBOARDING §7 table, DEVELOPMENT_LOG glossary (lines 38-54, the most complete) | A new `docs/GLOSSARY.md`. All three link to it. |
| Document map | INDEX (full), ONBOARDING §7 (16 rows), README §Documentation, site "Documentation" | INDEX. ONBOARDING keeps a 3-line pointer. |
| Test and case counts | README×2, TESTING×2, ONBOARDING×5, SURVEY×4, PAPER_NOTES, conformance README, log State lines | README and TESTING only (the guarded ones). Other docs say "see TESTING.md". |
| Parameter table | ALGORITHMS §10 and PAPER_NOTES §9: same 14 parameters, both with rationale, and the maintenance rule requires editing both | ALGORITHMS §10 (normative). PAPER_NOTES §9 keeps only the calibration history and links to §10. |
| Base-anchored lift vs peer MSA | PAPER_NOTES §5.3–5.4 (about 200 lines), COMPARISON "N-witness merge architecture", ALGORITHM_SURVEY §15–16 | PAPER_NOTES (rationale). COMPARISON keeps the CollateX contrast only. SURVEY keeps cost and weaknesses only. |
| Viewer views | ONBOARDING §6.2 table, PAPER_NOTES §8.1 table, VIEWER_UX_PLAN, README §viewer, site | A new viewer guide (user-facing) and PAPER_NOTES §8.1 (rationale). |
| Debug vs release trap | README, ONBOARDING §2, BENCHMARKS, corpus README, `--help`, site | Fine as a repeated warning. The explanation lives only in BENCHMARKS. |
| CLI usage | README §collate, ONBOARDING §2, corpus README, `--help`, CLI_PLAN | A new CLI guide. README keeps 6 lines. |

**PAPER_NOTES vs ALGORITHMS.** These are a real pair: ALGORITHMS is the normative spec, and PAPER_NOTES is the design rationale (the history of gate calibration, Appendix A on ML, §8.1 on the viewer, and the bibliography). They are not redundant, but the "update both for every feature" rule (CONTRIBUTING:115-118, INDEX:104-105) doubles the cost of every change. Make ALGORITHMS the only home for behaviour and parameters, and have PAPER_NOTES cite its sections. Consider renaming PAPER_NOTES to `DESIGN_NOTES.md` or `RATIONALE.md`. Note that 13 source and test comments cite `PAPER_NOTES`, so either keep the filename or leave a stub.

**DEVELOPMENT_LOG.** As a record it is excellent: dated, tagged, honest about negative results. It is hard to navigate: 2,266 lines, no table of contents, and dates repeated (four 2026-07-08 entries, plus 07-09/b/c and 07-13/b/c). Recommendations:
1. Add a generated table of contents at the top (date · tag · title · backlog ID; 58 rows).
2. Add a short "eras" summary in place of the frozen "at a glance" paragraph:
   - 06-26 to 06-28: foundations
   - 06-29 to 06-30: portability and evaluation
   - 07-01 to 07-06: CLI and the token-graph line
   - 07-07 to 07-13: viewer
   - 07-08 to 07-24: false-move gates
3. Do not split it: dates are the link targets used in ONBOARDING, BACKLOG and source comments. If it is split, use `docs/history/2026-06.md` and `2026-07.md` with the index in the old file.
4. Release-level changes go to a new CHANGELOG. The log stays for research and design decisions.
5. Keep it under `development/`, but describe it in INDEX as a historical record.

**Proposed `docs/` layout** (keep filenames that code cites; leave a stub wherever a cited file moves)

```
README.md  CHANGELOG.md(new)  CONTRIBUTING.md  SECURITY.md(new)  SUPPORT.md(new)  CODE_OF_CONDUCT.md
docs/
  INDEX.md                    rewritten for this layout
  RESEARCH_INTRO.md           unchanged; add links
  ONBOARDING.md               trimmed: §6 → pointers, §7 → pointer
  GLOSSARY.md                 new (merge the three vocabularies)
  guides/                     new: USER-facing
    CLI_GUIDE.md              every flag, menu walkthrough, files per format, exit codes 0/1/2/3, lexicon file format
    VIEWER_GUIDE.md           the 8 views, how to read them, constraints (from VIEWER_UX_PLAN §Constraints)
    LIBRARY_GUIDE.md          using CollationKit from Swift (see D)
    INPUT_FORMAT.md           witness files: .txt/.md, siglum = stem, page markers, no_collate, meta.json
  reference/                  ALGORITHMS, PAPER_NOTES (→ rationale), ALGORITHM_SURVEY, COMPARISON
  conformance/                unchanged
  development/                TESTING, BACKLOG, DEVELOPMENT_LOG(+ToC), CASE_STUDY, BENCHMARKS(+benchmarks/), RELEASING.md(new)
  proposals/                  CORPUS_PLAN.md, RUST_STANDALONE_PLAN.md (from porting/), each with a "Proposal — not built" banner
  archive/                    CLI_PLAN.md, TOKEN_GRAPH_PLAN.md, VIEWER_UX_PLAN.md, each with a banner:
                              "Historical design record; shipped <date>; current docs: …"
```

What moves or merges:
- TOKEN_GRAPH_PLAN §4: the "land it behind existing types; flip the default on evidence" discipline goes to CONTRIBUTING as "Landing a behaviour change".
- CLI_PLAN §0 (the layering rules) goes to an ONBOARDING "Architecture" subsection.
- VIEWER_UX_PLAN "Constraints" goes to VIEWER_GUIDE.

Links to fix after moving:
- `site/index.html` (11 GitHub doc links)
- README, INDEX, ONBOARDING, CONTRIBUTING, BACKLOG
- `.github/ISSUE_TEMPLATE/config.yml` (only RESEARCH_INTRO and ONBOARDING, which do not move)
- About 30 source and test comments citing `CLI_PLAN`, `TOKEN_GRAPH_PLAN.md` and `VIEWER_UX_PLAN`. Use a mechanical path update, or leave the files where they are with the banner added.
- `Package.swift:20` cites `CLI_PLAN.md §0`.

**Minimum change if a restructure is too much for 1.0:** add banners to the three shipped plans, label CORPUS_PLAN and RUST as proposals, add the log table of contents, and fix (B).

---

## (D) Missing documents for a 1.0

In priority order:

1. **Library usage guide (`LIBRARY_GUIDE.md`, or a DocC catalog).** This is the biggest gap. README sells an embeddable library, but no document shows `import CollationKit` or a SwiftPM `.package(url:…, from:)` line. That line cannot work anyway until there is a tag. The guide should show building a `Witness`, `Collation.collate(base:compared:)`, `variantGraph(witnesses:strategy:)`, `Normalizer` presets, `PaginationModel`, `TranslationLexicon`, `AlignmentScores.prose/.verse`, and rendering through `Apparatus`, `Synopsis`, `Report`, `CollationNarrative` and `CollationJSON`. Also needed: a statement of which public symbols are stable for 1.0. The baseline counts 238 `public` declarations in the engine, and none is marked internal-but-public.
2. **CHANGELOG.md.** Nothing records what is in 0.1.0 or 0.2.0. Start one with the 2026-09-25 release and an "Unreleased" section. The done ledger in the BACKLOG is the source.
3. **Versioning and release policy (`RELEASING.md`, or a CONTRIBUTING section).** It should cover:
   - SemVer for the Swift API, versioned separately from `CollationJSON.schemaVersion` (currently 3).
   - Whether a golden change is a minor or a major change. It is behaviour-visible for anyone citing an apparatus.
   - Tagging, and keeping `CITATION.cff`, `CollateCLI.version` and the site BibTeX in step. The site BibTeX has no version.
   - Regenerating the site demos (`site/build-demos.sh`, which no document mentions).
   - Re-recording benchmarks and re-measuring the corpus figures.
4. **CLI user guide.** CLI_PLAN §7 promised `CLI_GUIDE.md` and its status line admits it was never written. `--help` is the only reference, and it is out of date. Exit codes, the files written for each format, the manifest, the lexicon file format and the CSV columns are documented only in code or in the archived plan.
5. **Viewer guide.** How to read the 8 views is spread across an ONBOARDING table, a PAPER_NOTES table and a plan. The viewer is the main thing users see.
6. **Input-format guide.** Witness conventions are scattered:
   - the siglum is the filename stem, and `.txt` and `.md` are accepted
   - page markers `\f`, `<!-- page break -->` and a stand-alone `---`
   - `<!-- no_collate -->` regions
   - the lexicon line format
   - case `meta.json`
   - Note that a stand-alone `---` silently becomes a page break. Users of Markdown need to be warned about this.
7. **SECURITY.md.** The viewer embeds arbitrary witness text in HTML (`HTMLExportTests` has a `</script>` injection guard), so a reporting route matters. GitHub private vulnerability reporting is enough.
8. **SUPPORT.md**, or enable Discussions. Blank issues are disabled and there is no "question" template.
9. **GLOSSARY.md**, as in (C).
10. **Platform statement.** Only macOS 13 is declared and tested; CI runs macOS only for Swift. Say whether Linux and Windows are unsupported or simply untested.
11. **Known-limitations page**, or a README section linking one list. Today it is split between README §Status, PAPER_NOTES §11 (long and mostly "resolved") and the BACKLOG.

Not needed for 1.0: an API reference site, translations, a governance file (one maintainer; CODEOWNERS is enough).

---

## (E) BACKLOG triage

| Item | Verdict | Reason |
|---|---|---|
| **B6 — CJK tokenisation** | Defer (post-1.0); mark ☐, not ◐ | No CJK corpus or case exists. ICU or NaturalLanguage segmentation threatens the zero-dependency rule and cross-platform byte-stability (segmenter versions drift). State the limit in the 1.0 docs instead. |
| **B12 — TEI I/O** | Keep for 1.0, **export only**; defer import | TEI `<app>` export is the largest interoperability gap. COMPARISON:151-152 calls it the ecosystem shortfall. It is a new renderer beside `Apparatus`, with no golden risk. Import is larger, and parsing should stay outside the pure engine. If 1.0 must ship sooner, list it as the headline of 1.1. |
| **B13 Step 2 — UI strategy affordance** | Drop from this backlog; replace with an in-repo item | Its target UI is outside the repo. Replace it with "the interactive menu offers merge strategy, scoring and lexicon, defaulting through `contextualDefault`". This is small, it is 1.0 polish, and it would make the ONBOARDING:198 claim true. |
| **B9 Stage B — CLI release polish** | Keep for 1.0, partly | It is explicitly "gated on v1.0", and that time is now. In for 1.0: a single version string, `--version` without the "Stage A" tag, an accurate `--help`, overwrite confirmation (planned in CLI_PLAN:275-277, not built), and install instructions. Defer: man page, shell completions, `b`/`?` menu navigation. |
| **B15 — witness-profile artifact** | Defer to 1.1 | Additive and low-risk, but no 1.0 user needs it. It is the enabler for B16 and `collate-corpus`. |
| **B16 — corpus-wide commonness** | Defer (research) | Depends on B15. It is a research question (RESEARCH_INTRO §4.1). |
| **B17 — sentence-aligned anchors** | Defer (research) | The backlog itself says "Larger effort; defer until a corpus-scale translation need is concrete". |
| **B18 — nested moves** | Drop to the ideas list (survey Part II) | "Vanishingly rare", with no case demanding it. The README limits already cover it. |
| **B19 — adversarial benchmark point** | Keep for 1.0 | Small, touches `collate-bench` only, and closes a gap that BENCHMARKS:116-119/131-133 states. Do it together with re-recording the full sweep, which is needed anyway (B). |
| *Missing from the backlog: re-record benchmarks + CSV (B3 refresh)* | Add; 1.0 | The recorded data predates B11 and B14, and BENCHMARKS:22 already asks for it. |
| *Missing: Fenwick weighted LIS (Survey II-1)* | Add; good first issue, any release | ONBOARDING presents it as a backlog item, but it is not one. It changes no output. |
| *Missing: interned token keys and parallel pairwise (Survey Tier 4)* | Add as deferred | Performance only, with no golden risk. |
| *Missing: documentation set from (D)* | Add; 1.0 | Library guide, CLI guide, CHANGELOG, release policy. |
| *Missing: re-measure the Walter-pair figures after `build_corpus.sh`* | Add; 1.0 | Three docs quote three different numbers (B). |
| **Done ledger** | Keep | Accurate against the log. "Viewer UX: all 5 viewer items" is correct as of 07-08. The three later views (Changes, Alignment, Story) have no ledger row; add one ("Viewer views 6–8, 2026-07-10…13c"). |
| **"Recommended order"** | Rewrite for 1.0 | For 1.0: B12-export, B9-B (partial), the menu strategy item, B19 plus the benchmark refresh, and docs. After 1.0: B15 → B16/B17, B6. Ideas list: B18. |

---

## (F) The pre-release working copy

The maintainer's pre-release working copy (outside this repository) was compared file by file with the release.

- **Shared files differ only in wording** that was scrubbed for publication (internal names and planning
  references). Every non-comment Swift line was checked: there are no behavioural code differences.
- **Files that exist only in the working copy** are a welcome pack for research students and the drafts of the
  two papers in preparation. Both correctly stay private: they refer to material shared only with collaborators.
  The welcome pack's short reading order (website → RESEARCH_INTRO → ONBOARDING → CASE_STUDY → by interest) and its
  three day-one tips are clearer than the top of ONBOARDING, so a public "Start here in 30 minutes" box could
  reuse them.
- **One substantive limit was lost in the transfer.** The working copy's README noted that readings are
  reconstructed by joining token surfaces with single spaces. That is still true, and the public README should
  say so again (see B).

---

## Incidental findings (outside the docs, for the CLI/engine reviewers)

- **Narrative grammar.** `summary.txt` on mysterious-island reads "3 passages were relocated; 3 of these are reported as *possible* moves …, the rest as certain". When none are certain, "the rest as certain" should be dropped. This is in `CollationNarrative`.
- **Missing move in the apparatus.** `collate run MS.txt UNI.txt` on case 16 lists the transposition in the located report, but the CRITICAL APPARATUS section shows only the 4 substitutions and not the move. Worth checking whether an apparatus is meant to omit moves.
