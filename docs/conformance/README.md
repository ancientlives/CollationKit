# Conformance corpus + interchange schema

This directory is the **portability contract made executable**. It pins what the engine produces so any
re-implementation can be *verified*, not just hoped at, and it doubles as the paper's reproducibility
artifact. It implements backlog items **B1** (conformance corpus + golden JSON) and **B2** (formal JSON
Schema) — see [`../development/BACKLOG.md`](../development/BACKLOG.md).

```
conformance/
  README.md                  ← you are here
  collation.schema.json      ← B2: JSON Schema (draft 2020-12) for the `{ graph, pairs }` interchange
  validate.py                ← validate every golden against the schema (language-neutral check)
  requirements.txt           ← Python deps for validate.py (jsonschema)
  cases/                     ← B1: input witness sets, one directory per case
    01-substitution/
      meta.json              ← how to collate this case (base, order, options)
      A.txt, B.txt           ← witnesses; filename (sans .txt) is the siglum
    …
  golden/                    ← B1: expected `--json` output, one file per case
    01-substitution.json
    …
```

## What a "case" is

Each directory under `cases/` is one witness set plus a `meta.json`:

| field               | meaning |
|---------------------|---------|
| `name`              | short case name |
| `description`       | what the case exercises |
| `base`              | siglum of the base witness (first in `witnessOrder`) |
| `witnessOrder`      | sigla in collation order; each must have a matching `<siglum>.txt` |
| `recordAccidentals` | `true` to surface folded spelling/accidental variants (`variantSpelling`) |
| `recordPunctuation` | *(optional, default `false`)* `true` for the **diplomatic** overlay — report punctuation-only differences as accidentals (B6b) |
| `pagination`        | `"default"`, `"throughNumbered"`, or `{ "linesPerPage": N }` |
| `normalizer`        | `"substantive"` (default), `"gbUS"` (GB/US spelling folded), or `"diplomatic"` |
| `strategy`          | *(optional, default `"base-anchored"`)* the N-witness merge strategy: `"base-anchored"` or `"peer-msa"` (B14). A case pinned to `peer-msa` verifies a port's peer merge; a base-anchored-only port skips strategy-pinned cases. |
| `lexicon`           | *(optional, B10)* inline translation-equivalence groups (`[["l'année","year"], …]`) applied as alignment-key pivots for cross-language cases; forms are matched case-insensitively against normalised tokens. |

These map one-to-one onto the engine's public options (`Normalizer`, `PaginationModel`,
`recordAccidentals`, `recordPunctuation`, `CollationStrategy`, `TranslationLexicon`) and the CLI flags.

The corpus spans the engine's behaviour matrix — substitution, insertion, deletion, transposition (clean
and move-with-internal-edit), GB/US spelling folded vs. recorded as accidentals, a ≥3-witness variant
graph, agreement-only, a reworded clause as a single substitution, page-aware citation
(`linesPerPage`) and through-numbering, apostrophe/hyphen and non-Latin (Greek) tokenisation, mixed
variants in one pair, and the built-in six-edition fixture. The corpus is **29 cases**. **Nine** of them
are **real, public-domain** passages, not crafted fixtures — the nine numbered case studies (conformance
cases 17–24 and 27) analysed in [`../development/CASE_STUDY.md`](../development/CASE_STUDY.md) (BACKLOG B4);
each `meta.json` carries source provenance (and any OCR-correction or semi-synthetic caveat): Frankenstein
1818/1831 (accidental-heavy), Whitman *Song of Myself* 1855/1891 (substantive insertion), Whitman
transposition (relocated line — *semi-synthetic*), Verne Mercier vs Walter (translation collation), Verne
two French editions (French tokenisation), **Verne French + 2 English (N-witness cross-language graph)**,
**Whitman 1855/1860/1891 (N-witness three editions)**, **Pushkin (Cyrillic tokenisation)**, and **the
*found* Whitman *Calamus* poem-cluster transposition (1860→1867)**. Three authors, three scripts (Latin,
Greek elsewhere, Cyrillic), and both pairwise and N-witness counts. Cases 25–26 and 28–29 are further
fixtures built from the same material — single-word-move regression (25), the Frankenstein *diplomatic*
(punctuation) view (26), a peer-MSA base-sensitivity case (28), and the trilingual peer/lexicon Verne case
(29) — the last two **strategy-pinned** (`peer-msa`) so a peer-merge port is exercised.

## The golden output

`golden/<case>.json` is the expected `{ graph, pairs }` interchange — the **exact** artifact
`collate-demo --json` prints, produced by the same code path (`CollationJSON.outputString`). Output is
deterministic (sorted keys, sorted readings/sigla) per the rules in
[`../reference/ALGORITHMS.md` §9](../reference/ALGORITHMS.md); a conforming port must reproduce each
golden **byte-for-byte** (modulo those rules), with the case siglum (not a filename) as each witness id.

## How a port passes

1. Read each case's `meta.json` and witness files.
2. Collate with the stated options and emit the `{ graph, pairs }` JSON.
3. Compare to `golden/<case>.json` byte-for-byte. All cases must match.
4. (Optional but recommended) validate your output against `collation.schema.json`.

## Verifying & refreshing the goldens

The Swift reference checks the goldens as part of the test suite:

```sh
swift test --filter Conformance                      # verify the engine still reproduces every golden
COLLATION_RECORD=1 swift test --filter Conformance   # REGENERATE goldens after an INTENTIONAL change
```

Only regenerate when a behaviour change is intended — then review the golden diff before committing, and
add a dated [`DEVELOPMENT_LOG.md`](../development/DEVELOPMENT_LOG.md) entry explaining what changed and
why the wire output moved.

## Validating against the schema

```sh
python3 -m venv .venv && . .venv/bin/activate
pip install -r docs/conformance/requirements.txt
python3 docs/conformance/validate.py                 # exit 0 iff every golden validates
```

`validate.py` is language-neutral: a port in any language can reuse `collation.schema.json` and this
script to confirm its own output conforms to the interchange. The Swift suite additionally asserts
conformance structurally (`ConformanceTests.testGoldensConformToInterchangeShape`) without a validator
dependency, and checks that the schema's `schemaVersion` const stays in step with
`CollationJSON.schemaVersion`.
