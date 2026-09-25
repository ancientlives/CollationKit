# Corpus collation — plan for a multi-work wrapper (`collate-corpus`)

**Status:** design / proposal (not built). Written 2026-07-09 in answer to: *should collating many works of an
author (e.g. every extant edition of every Verne novel) live inside the engine, or in a separate wrapper that can
publish a website / export of the collated material?*

This is the corpus counterpart of [`VIEWER_UX_PLAN.md`](VIEWER_UX_PLAN.md) (single-collation viewer) and
[`TOKEN_GRAPH_PLAN.md`](TOKEN_GRAPH_PLAN.md) (an engine change): it specs a **new product built on top of the
existing engine**, not a change to the engine.

---

## 0. Decision: keep the engine single-work; build a separate wrapper

**Recommendation — a separate `collate-corpus` product, not corpus logic inside `CollationKit`.**

The reasoning is a direct consequence of what the engine *is*:

- **The engine's value is that it is a pure, deterministic function of `(witnesses + declared config) → one
  collation`.** That purity is what makes it testable, portable (the conformance corpus + JSON Schema), and — for
  scholarship — reproducible and citable (see `PAPER_NOTES.md` Appendix A). A corpus is a *different kind of
  object*: it is about **organising, relating, and publishing many collations** — catalogues, cross-work
  navigation, per-work configuration, incremental rebuilds, a site generator. Pushing that into the engine would
  blur a clean seam and bloat the portability contract. **One collation is an algorithm; a corpus is a project.**
- **The seam already exists.** A corpus is just *N runs of the existing engine, indexed*. Each work already
  produces a self-describing output set (`collation.json` + `collation.html` + `apparatus.txt` + `manifest.txt`
  via `Exporter`), and the corpus test material already uses a `meta.json` per work
  (`docs/conformance/cases/*/meta.json`, `corpus/verne/*/meta.json`) that captures work/witness/source
  metadata. A corpus tool **orchestrates** that; it needs no new engine capability for the core case.
- **What is genuinely new in a corpus is cataloguing, not alignment** — e.g. "the same 1873 Mercier translation
  recurs across several novels", "these French source editions are shared". That is *metadata + linking*, which
  belongs in the wrapper, and reinforces that the engine stays as-is.

**Non-goal:** this plan does **not** introduce cross-document *learning* or shared adaptive state (rejected in
`PAPER_NOTES.md` Appendix A). Every collation in a corpus remains an independent, reproducible function of its own
witnesses + declared config. The corpus only adds *organisation* around those independent results.

---

## 1. Scope & tiers

Three tiers, so scope is a choice. **Recommended start: Tier B.**

| Tier | What it is | When |
|------|-----------|------|
| **A — batch CLI** (smallest) | `collate-corpus <manifest>` runs the engine over many works and writes each work's existing output set + a top-level `corpus.json` index. No new UI. | You mainly want *the data* for all works, scriptably. Pure orchestration; lowest effort. |
| **B — static corpus site** (recommended) | A **+ a site generator**: an author/works index page linking each work's (existing) interactive viewer, corpus-wide "what was detected" aggregates, and cross-work navigation. Self-contained, deployable to any static host. | The "publish a website of collated Verne" goal. Highest value per effort; builds directly on the shipped viewer. |
| **C — interactive corpus app** (largest) | A living app (SwiftUI or web) to browse, re-run, and *edit* the corpus interactively. | Only if editors must *work in* the corpus, not just read a published artifact. Defer until B proves the model. |

Tiers are additive: B contains A's index; C would consume B's build output.

---

## 2. Architecture — a new product on the existing engine

Add one Swift package product; touch no existing target's behaviour.

```
Package.swift
  targets:
    CollationKit        (unchanged — the engine)
    CollateCLI          (unchanged — CollationRunner, Exporter, HTMLExport)
    collate             (unchanged — the single-work CLI)
    CollationCorpus     (NEW library: manifest model, orchestrator, incremental cache, site generator)
    collate-corpus      (NEW executable: thin shell over CollationCorpus)
```

`CollationCorpus` depends on `CollateCLI` (for `CollationRunner` + `Exporter` + `HTMLExport`) and `CollationKit`.
It reuses, and never re-implements, the engine and the viewer:

- per-work collation → `CollationRunner.run(opts, witnesses:, includeViewerPairs: true, …)` (exactly as `collate`
  does);
- per-work artifacts → `Exporter.files(for: run)` (the same `collation.json` / `collation.html` / reports);
- the interactive page → the existing `HTMLExport` template, unchanged.

**Determinism carries up.** Given the same corpus manifest + same input files, `collate-corpus` produces
byte-identical output (sorted iteration, stable ids, no timestamps except an optional, clearly-marked build stamp
that is excluded from the content hash). This keeps the corpus itself reproducible, the same property the engine
guarantees per work.

---

## 3. The corpus manifest (input)

A single declarative file (`corpus.json` or `corpus.toml`) the editor owns — the corpus analogue of the per-work
`meta.json`, which it subsumes. Everything the build needs is here; nothing is inferred. This is the "explicit,
user-owned configuration" `PAPER_NOTES.md` Appendix A argues for, at corpus scale.

```jsonc
{
  "schemaVersion": 1,
  "corpus": {
    "id": "verne",
    "title": "The Collated Verne",
    "author": "Jules Verne",
    "description": "Collations of the extant editions/translations of Verne's novels.",
    "language": "mixed"            // informational
  },
  "defaults": {                    // per-work overrides fall back to these (all optional)
    "strategy": "baseAnchored",    // or "peerMSA"
    "scoring": "prose",            // or "verse"
    "normalizer": "substantive",   // or "diplomatic"
    "recordAccidentals": false,
    "recordPunctuation": false,
    "pagination": "default"
  },
  "lexicons": {                    // reusable, referenced by id from a work (B10 cross-language)
    "fr-en": "lexicons/fr-en.lex"
  },
  "works": [
    {
      "id": "20000-leagues",
      "title": "Twenty Thousand Leagues Under the Seas",
      "originalTitle": "Vingt mille lieues sous les mers",
      "year": 1870,
      "base": "walter",
      "witnessOrder": ["walter", "mercier"],
      "witnesses": {
        "walter":  { "file": "works/20000-leagues/walter.txt",
                     "label": "F. P. Walter (modern, unabridged)",
                     "source": "Project Gutenberg #2488", "year": 1999 },
        "mercier": { "file": "works/20000-leagues/mercier.txt",
                     "label": "Lewis Mercier (Sampson Low, 1872 'standard')",
                     "source": "Project Gutenberg #164", "year": 1872 }
      },
      "collate": { "strategy": "baseAnchored" }   // overrides defaults for this work
      // "lexicon": "fr-en"  // reference a shared lexicon when the set is cross-language
    }
    // … one entry per novel …
  ]
}
```

Notes:
- **`file` paths are relative to the manifest**, so a corpus directory is portable/checkout-able.
- The per-work `witnesses[*]` metadata (label, source, year) is richer than the engine needs — it is *catalogue*
  data the site renders; the engine only consumes the text + the `collate` block.
- **Witness identity across works** (§8) is expressed by a stable witness `id` + optional `sameAs` link, so the
  site can note "the Mercier translation also appears in …" without the engine knowing or caring.

---

## 4. Orchestration & the incremental cache

The build is embarrassingly parallel (works are independent) and must be **incremental** — re-collating "all of
Verne" on every edit is unacceptable.

```
for each work in manifest.works:
    key = hash( work.witness file contents  +  resolved collate config  +  engine version )
    if cache[work.id] == key and artifacts present:  skip (reuse)
    else:  run CollationRunner → Exporter.files → write; cache[work.id] = key
build corpus.json index (always cheap) and the site (Tier B)
```

- **Content-addressed cache.** The key is a hash of *inputs*, not a timestamp, so determinism holds and only
  genuinely-changed works rebuild. Bumping the **engine version** in the key invalidates everything (correct: a
  new engine may collate differently).
- **Parallelism.** Works run concurrently (bounded pool); each `CollationRunner.run` is already pure and
  thread-safe (value types, no shared state). The full novel collates in seconds (`BENCHMARKS.md`), so a
  dozen-novel corpus is minutes cold, near-instant warm.
- **Progress + failure isolation.** Per-work progress to stderr (reusing the runner's `progress:` channel); a
  work that fails (e.g. a missing file) is reported and skipped, not fatal — the rest of the corpus still builds.

---

## 5. Outputs

### 5.1 Data (Tier A and up)
- Per work: the existing `collation.json` + `collation.html` + `apparatus.txt` + `manifest.txt`, under
  `out/works/<id>/`.
- `out/corpus.json` — the corpus **index**: the manifest's catalogue metadata + per-work summary stats
  (witness count, variation counts by type, spine/graph shape — all already on `CollationRun`/the HTML payload's
  `summary`) + the path to each work's artifacts. Sorted keys, deterministic. This is the machine-readable
  corpus, the reproducibility artifact for the whole set (analogue of the single-work JSON).

### 5.2 Static site (Tier B)
Self-contained HTML (same CSP discipline as the viewer — no external fetches; inline or same-origin assets only),
deployable to any static host:

- **Corpus home** — author, description, a **works grid/dashboard** (reusing the viewer's stat-tile + bar-chart
  vocabulary from the Overview dashboard), corpus-wide aggregates ("across N works: X substitutions, Y moves…"),
  and a witness catalogue (each edition/translation, which works it appears in).
- **Per-work page** — the existing interactive `collation.html`, unchanged, linked from the home. (Optionally
  wrapped with a corpus header/breadcrumb; the viewer stays a pure function of its run.)
- **Cross-work navigation & search** — jump between works; a client-side index over apparatus lemmas/readings so
  a user can find "where does witness X read Y across the corpus" (static JSON, no server).

The site generator is the genuinely new UI code; everything under it is the shipped viewer.

---

## 6. Constraints (inherited)

- **Self-contained, CSP-safe** pages (as the viewer): no external scripts/fonts/fetch; inline or same-origin.
- **Deterministic**: byte-stable output for stable inputs; the only non-determinism is an optional build stamp
  excluded from hashing.
- **Engine untouched**: `CollationKit` and its conformance goldens do not change. If a corpus *need* ever forces
  an engine change, that change goes through the normal engine process (spec in `ALGORITHMS.md`/`PAPER_NOTES.md`,
  a golden), separately from the wrapper.
- **Reuse, don't fork**: per-work collation and rendering go through `CollationRunner`/`Exporter`/`HTMLExport`.

---

## 7. Testing

- **Unit** (in a new `CollationCorpusTests`): manifest parsing (incl. defaults/override resolution and lexicon
  references), the incremental-cache key (same inputs → skip; changed input/config/engine-version → rebuild),
  `corpus.json` shape + determinism, failure isolation (one bad work doesn't sink the build).
- **A tiny golden corpus**: 2–3 miniature works under a test fixture, with a committed expected `corpus.json`, so
  a corpus build is regression-guarded the same way single collations are.
- **Site**: the generated HTML verified in WebKit via a Playwright harness, not included (links resolve, the works
  grid renders, a per-work viewer opens) — the same discipline as the viewer.

---

## 8. Open questions (decide when building)

- **Cross-work witness identity.** How rich should `sameAs` be — a free string, or a first-class shared-witness
  registry with its own pages? (Start simple: a stable id + an optional label; upgrade if the catalogue demands.)
- **Corpus-level aggregates that need alignment.** Everything in §5 is *summation* of per-work results (cheap,
  no new alignment). *If* a future feature wanted, say, "align the same passage across three different novels",
  that is a real new alignment problem and would belong to the engine, not the wrapper — explicitly out of scope
  here.
- **Manifest format** — JSON (parses everywhere, matches the interchange) vs. TOML/YAML (friendlier to hand-edit
  a large corpus). Recommendation: JSON as the canonical form, with an optional convenience loader.
- **Hosting story** — the site is static, so anything works; a `--base-url` for sub-path deploys is the only
  likely knob.

---

## 9. Relationship to the roadmap

- Independent of, and complementary to, any native single-work collation viewer (future work): this is a
  multi-work *publishing* tool. They would share the engine, not the UI.
- Sits above **B8** (the interactive viewer, shipped) — the per-work page a corpus links to is exactly B8's
  `collation.html`.
- A natural **paper artifact**: "the collated Verne" would be a concrete, browsable demonstration of the engine
  at corpus scale, and its build is a reproducibility story (manifest + inputs → byte-stable site).
