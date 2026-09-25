# Verne collation test corpus

Real **variant English editions of Jules Verne novels** (public domain, with one exception noted below), prepared as clean witnesses for the
CollationKit engine and the `collate` CLI. English Verne is always a **translation** of the French original,
so a work's "variant editions" are its different English translations (and the different years/regions those
translations were published in) — each a witness of the same underlying novel. Two competing translations of
one novel diverge heavily in wording, which is exactly the substantive variation a collation engine exists to
surface.

## Layout

```
corpus/verne/
  raw/                     raw Project Gutenberg downloads (pgNNN.txt) — never edited by hand; not committed
                           (git-ignored), recreated by scripts/build_corpus.sh
  scripts/
    clean_gutenberg.py     the reusable cleaner: strip Gutenberg boundaries/notes, normalise, excerpt
    build_corpus.sh        downloads + builds the whole corpus (reproducible; re-run any time)
  <work>/
    <siglum>.txt           one cleaned witness per translation (a chapter excerpt) — the routine test unit
    full/<siglum>.txt      the whole-novel witnesses (only where a scale test is wanted), in a subfolder so
                           `--dir <work> --all` sees only the excerpt witnesses
    meta.json              provenance + how to collate (mirrors docs/conformance/cases/*/meta.json)
  known-issues/            engine findings this corpus surfaced, with reproducers
  BIBLIOGRAPHY.md          working bibliography (+ bibliography.json): editions, translations, sources
  README.md                this file
```

The witness files contain **only the text** — no title/provenance comment (that would tokenise as spurious
words; the engine only treats the exact marker `<!-- page break -->` specially). All provenance lives in
`meta.json`.

## What's here now

| work | witnesses (translations) | source | scale | ~variants (Ch.1) | full-novel pair (`full/`) |
|------|--------------------------|--------|-------|------------------|---------------------------|
| `20000-leagues` | `mercier` (Sampson Low, 1872 std.) · `walter` (modern, unabridged) | PG164 · PG2488 | Ch.1 excerpt **+ full novel** | 403 | ~21.5k variants, ~9 s; align 4.8% drift / 98.9% mono |
| `earth-to-moon` | `towle` (From the Earth to the Moon) · `moonvoyage` (The Moon-Voyage) | PG83 · PG12901 | Ch.1 excerpt **+ full novel** | 329 | ~7.4k variants, ~2 s; align 9.4% / 98.3% |
| `journey-centre-earth` | `malleson` (Liedenbrock) · `ward` (Von Hardwigg) | PG3748 · PG18857 | Ch.1 excerpt **+ full novel** | 157 | ~12.8k variants, ~4.5 s; align 12% / 98.6% (ward is a re-write, ~16% longer) |
| `mysterious-island` | `kingston` · `white` | PG1268 · PG8993 | Ch.1 excerpt **+ full novel** | 388 | ~31.8k variants, ~15 s — the **largest** pair; align 4.9% / 98.0% |

Every Chapter-1 pair is a genuine, demanding substantive-variation test (heavy substitution + transposition +
edits-within-moves); the two `journey-centre-earth` translations even name the professor differently
(Liedenbrock vs Von Hardwigg). **Each work now also has a `full/` whole-novel pair** for scale collation
testing — `mysterious-island` is the largest (~195k / 167k words, ~15 s), and `journey-centre-earth` is a
demanding *structural-divergence* case (the ward edition is a complete re-write, ~16% longer — the alignment
map shows a clean but consistently-off-diagonal line, i.e. a correct alignment of two very different editions).
Full-novel witnesses exclude each edition's differing front matter via `<!-- no_collate -->` regions so only the
novel body is collated. The `20000-leagues` full novels *found a real engine crash* (an inverted-range trap),
now fixed and guarded; see [`known-issues/`](known-issues/). Per-work stats live in each `meta.json`'s `full`
block.

## Build / rebuild

```sh
bash corpus/verne/scripts/build_corpus.sh   # downloads missing raw texts, (re)builds every cleaned witness
```

## Collate them (the `collate` CLI, from the repository root)

```sh
cd CollationKit            # the repository root (your clone)
swift run collate run corpus/verne/20000-leagues/mercier.txt corpus/verne/20000-leagues/walter.txt   # after build_corpus.sh (walter is fetched locally)
swift run collate run corpus/verne/earth-to-moon/{towle,moonvoyage}.txt --format csv
swift run collate list --dir corpus/verne/20000-leagues            # the two excerpt witnesses
# the full-novel scale pairs (build -c release for these — a debug build is many times slower):
#   .build/release/collate run corpus/verne/20000-leagues/full/{mercier,walter}.txt --out /tmp/out
#   .build/release/collate run corpus/verne/mysterious-island/full/{kingston,white}.txt --out /tmp/out  # largest
#   .build/release/collate run corpus/verne/journey-centre-earth/full/{malleson,ward}.txt --out /tmp/out
#   .build/release/collate run corpus/verne/earth-to-moon/full/{towle,moonvoyage}.txt --out /tmp/out
# interactive:
swift run collate --dir corpus/verne/earth-to-moon
```

Each `<work>/meta.json` records the base witness and the recommended collate options (normaliser, pagination,
accidentals) so a run matches how the case is meant to be compared.

## Adding a new novel (the repeatable recipe)

The whole point of the scripted pipeline is that any Verne novel — or any Gutenberg work — can be added the
same way (the commands below run from `corpus/verne/`):

1. **Find competing translations.** Search Project Gutenberg for the work; note the eBook IDs of two (or more)
   distinct English translations/editions. English Verne translations to look for include different
   translators, and 19th-century UK vs later editions.
2. **Download the raw texts** into `raw/` (add a `fetch <id>` line in `build_corpus.sh`, or
   `curl -o raw/pgNNN.txt https://www.gutenberg.org/cache/epub/NNN/pgNNN.txt`).
3. **Find the chapter headings** so you can excerpt a comparable passage from each edition:
   `grep -nE '^(CHAPTER|PART|[IVXLC]+\.)' raw/pgNNN.txt | head`. Translations format headings differently
   (`CHAPTER I` vs `CHAPTER 1` vs a descriptive title), so each witness gets its own `--from-marker`/`--to-marker`.
4. **Clean + excerpt** each witness (add lines to `build_corpus.sh`):
   ```sh
   python3 scripts/clean_gutenberg.py raw/pgNNN.txt <work>/<siglum>.txt \
       --from-marker '^CHAPTER I$' --to-marker '^CHAPTER II$'
   ```
   **For a scale test, also emit a whole-novel witness into `full/`** (no `--from/--to`, so the whole book):
   ```sh
   python3 scripts/clean_gutenberg.py raw/pgNNN.txt <work>/full/<siglum>.txt \
       --no-collate-until '^CHAPTER I\.'
   ```
   `--no-collate-until '<first-body-heading>'` wraps each edition's differing front matter (title page /
   redactor's or transcriber's note / TOC) in a `<!-- no_collate -->` region so it is excluded from collation
   (otherwise the mismatched front matter generates junk variants and skews the alignment). If both eBooks
   bundle more than one novel, add `--to-marker` to keep only the shared work (as `earth-to-moon` does).
5. **Verify** the excerpts genuinely overlap in content (same scene, different wording) — eyeball the heads:
   `head <work>/*.txt`.
6. **Write `<work>/meta.json`** — copy an existing one; record each witness's translator, Gutenberg ID,
   the excerpt boundaries, the base, and the collate options.
7. **Collate and sanity-check** with the CLI; if a real edition exposes an engine bug (as the full novels did),
   note it in `known-issues/` with a minimal reproducer.

### Cleaning specifics (what `clean_gutenberg.py` does and doesn't do)

- **Does:** strip the Gutenberg START/END licence boundary; drop producer/transcriber/`[Illustration]` lines;
  normalise line endings + collapse blank runs (preserving paragraph breaks); optionally excerpt by heading
  (`--from-marker`/`--to-marker`); optionally wrap leading front matter in a `<!-- no_collate -->` region
  (`--no-collate-until`) so it is kept for display but excluded from collation.
- **Doesn't:** touch spelling, punctuation, or wording — those are the variants the engine must see.
  Substantive vs accidental folding (US/UK spelling, punctuation) is the **engine's** job via its normaliser
  (`--diplomatic`, `--accidentals`), not the cleaner's.

## Provenance & licence

All raw texts are from Project Gutenberg; each work's `meta.json` records the exact eBook IDs and retrieval
date (2026-07-01). Gutenberg's own trademark/licence header is stripped from the witnesses (that's the boundary
the cleaner removes); consult gutenberg.org for its terms.

Every committed witness is in the public domain in the US, **except one that is deliberately not committed**:

> **The F. P. Walter translation of *Twenty Thousand Leagues* (PG2488) is in copyright** (© 1999 Frederick Paul
> Walter; Project Gutenberg distributes it under its own licence). Its witnesses — `20000-leagues/walter.txt`,
> `20000-leagues/full/walter.txt` and `known-issues/repro-walter-700.txt` — are therefore **not in this
> repository**. Running `bash corpus/verne/scripts/build_corpus.sh` downloads PG2488 to your machine and rebuilds
> all three, byte-identical to the files the project's published results were produced from (the hand-placed
> `no_collate` markers for the full novel are kept in `scripts/walter-full.marks.json`, which contains marker
> positions only). The files are git-ignored so they cannot be committed by accident. Until you run the script,
> the `20000-leagues` pair has only its `mercier` witness.
>
> The conformance cases 20, 22 and 29 (`docs/conformance/cases/`) each contain the same 87-word opening paragraph
> of the Walter translation, as a short attributed quotation for research and testing; see `LICENSE-docs.md`.
