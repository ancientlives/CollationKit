#!/usr/bin/env bash
# build_corpus.sh — assemble the Jules Verne collation test corpus from raw Gutenberg texts.
#
# Reproducible end-to-end: (1) download raw texts into raw/ (if missing), (2) clean + excerpt each into
# <work>/ as witnesses via scripts/clean_gutenberg.py. English Verne is always a TRANSLATION of the
# French original, so each witness is a distinct English translation/edition of the SAME underlying work — the
# variant-editions material the collation engine is built to compare.
#
# Layout produced (under corpus/verne/):
#   <work>/<siglum>.txt          one cleaned witness per translation (chapter excerpt)
#   <work>/full/<siglum>.txt     the whole-novel witness (scale pair)
#   <work>/meta.json             provenance + how to collate (mirrors docs/conformance/cases/*/meta.json)
#
# Re-run any time: it re-downloads only missing raw files and OVERWRITES the cleaned .txt witnesses in place.
# It does NOT touch (or regenerate) the hand-maintained meta.json provenance files — so DO NOT delete the work
# folders to "rebuild"; that would delete the meta.json files, which are not produced here. Just re-run the script.
# NOTE: witnesses carry NO title/provenance comment (that would tokenise as spurious words); provenance lives
# in each work's meta.json. Invocations are kept on ONE line each (no backslash continuations) on purpose.
#
# To ADD A NEW NOVEL: pick its competing-translation Gutenberg IDs, add a `fetch` + one clean line per witness
# with the right --from-marker/--to-marker (find headings with `grep -nE '^CHAPTER' raw/pgNNN.txt`), and write
# a meta.json. See corpus/verne/README.md for the full walkthrough.
set -euo pipefail
cd "$(dirname "$0")/.."          # corpus/verne/
CLEAN="python3 scripts/clean_gutenberg.py"
mkdir -p raw

fetch() {  # fetch <id> — download pgID.txt into raw/ if absent
  local id="$1"
  [ -s "raw/pg$id.txt" ] || curl -s --max-time 60 -o "raw/pg$id.txt" "https://www.gutenberg.org/cache/epub/$id/pg$id.txt"
}

for id in 164 2488 83 12901 103 3748 18857 1268 8993; do fetch "$id"; done

# FRENCH SOURCE TEXTS (the originals — for future French<->English or French-French collation). Downloaded into
# raw/ so they are AVAILABLE; no cleaned witnesses are built from them by default (the French section below is
# commented out). Verified present & genuine 2026-07-24. See ../BIBLIOGRAPHY.md for the mapping.
#   pg5097  = Vingt mille lieues sous les mers (Complete)      [20000-leagues French original]
#   pg38674 = De la terre à la lune                            [earth-to-moon French original]
#   pg4791  = Voyage au centre de la Terre                     [journey-centre-earth French original]
#   pg14287 = L'île mystérieuse                                [mysterious-island French original]
# NOTE pg4791 (Journey, FR) is a Gallica/BnF OCR text with a French+English preface — use --no-collate-until.
# NOTE the French 'Le Tour du monde' (Around the World) ID is UNRESOLVED: gutenberg id 20973 404s on both the
#   cache/epub and files paths — find the correct FR id before adding it. See BIBLIOGRAPHY.md.
for id in 5097 38674 4791 14287; do fetch "$id"; done

# WORK 1 — Twenty Thousand Leagues Under the Sea(s)   [the SCALE pair: excerpt + full novel]
#   mercier = L. P. Mercier / Sampson Low, 1872 UK 'standard' translation (PG164, abridging/altering)
#   walter  = F. P. Walter modern faithful/unabridged translation (PG2488). COPYRIGHTED (c) 1999 F. P. Walter,
#             distributed by Project Gutenberg under its licence — so the Walter witnesses are NOT committed to
#             this repository; this script rebuilds them locally from your own download (they are git-ignored).
mkdir -p 20000-leagues
$CLEAN raw/pg164.txt  20000-leagues/mercier.txt --from-marker '^CHAPTER I$' --to-marker '^CHAPTER II$'
$CLEAN raw/pg2488.txt 20000-leagues/walter.txt  --from-marker '^CHAPTER 1$' --to-marker '^CHAPTER 2$'
# Full-novel witnesses (scale/benchmark): whole book, boundaries + notes cleaned, no excerpting. Kept in a
# full/ SUBFOLDER so `collate --dir corpus/verne/20000-leagues --all` sees only the two excerpt witnesses (the
# routine unit); collate the scale pair explicitly from full/. Their front matter was hand-wrapped in
# `<!-- no_collate -->` (the heading 'FIRST PART'/'PART ONE' occurs twice — TOC then body — so a plain
# --no-collate-until would stop at the TOC; the committed files exclude up to the SECOND occurrence). The Mercier
# line is commented out so re-running the script does NOT overwrite its hand-marked (committed) witness.
mkdir -p 20000-leagues/full
# $CLEAN raw/pg164.txt  20000-leagues/full/mercier.txt   # (kept hand-marked — see note above)
# The Walter full witness is not committed (see above), so it is rebuilt here: clean the whole book, then
# re-apply the hand-placed no_collate markers (positions only, kept in scripts/walter-full.marks.json). The
# result is byte-identical to the witness the project's results were produced from.
$CLEAN raw/pg2488.txt 20000-leagues/full/walter.unmarked.txt
python3 scripts/apply_marks.py 20000-leagues/full/walter.unmarked.txt scripts/walter-full.marks.json 20000-leagues/full/walter.txt
# known-issues reproducer: the first 700 lines of the unmarked Walter full text (see known-issues/README.md).
head -700 20000-leagues/full/walter.unmarked.txt > known-issues/repro-walter-700.txt
rm -f 20000-leagues/full/walter.unmarked.txt

# WORK 2 — From the Earth to the Moon  [competing translations of the SAME opening chapter, 'The Gun Club']
#   towle      = Mercier & King tr., 'From the Earth to the Moon; and, Round the Moon' (PG83).
#                NB: siglum 'towle' is a LEGACY MISATTRIBUTION (corrected 2026-07-24) — it is NOT George M. Towle;
#                kept only as an opaque id to avoid renaming files. Actual translator: Lewis P. Mercier & E. King.
#   moonvoyage = 'The Moon-Voyage' — a DIFFERENT English translation (PG12901), probably T. H. Linklater (1877).
# NOTE: both PG83 and PG12901 bundle TWO novels — 'From the Earth to the Moon' then its sequel 'Round the Moon';
# the full/ witnesses take ONLY the first novel (stop at '^ROUND THE MOON') so the pair collates like-for-like.
mkdir -p earth-to-moon earth-to-moon/full
$CLEAN raw/pg83.txt    earth-to-moon/towle.txt      --from-marker '^CHAPTER I\.' --to-marker '^CHAPTER II\.'
$CLEAN raw/pg12901.txt earth-to-moon/moonvoyage.txt --from-marker '^THE GUN CLUB\.' --to-marker '^PRESIDENT BARBICANE'
$CLEAN raw/pg83.txt    earth-to-moon/full/towle.txt      --from-marker '^CHAPTER I\.' --to-marker '^ROUND THE MOON'
$CLEAN raw/pg12901.txt earth-to-moon/full/moonvoyage.txt --from-marker '^THE GUN CLUB\.' --to-marker '^ROUND THE MOON\.'

# WORK 3 — Journey to the Centre of the Earth  [two famously divergent English translations, Ch.1]
#   malleson = F. A. Malleson translation, 'A Journey into the Interior of the Earth' (PG3748)
#   ward     = the 'A Journey to the Centre of the Earth' translation (PG18857)
# Both open on Professor Liedenbrock on 24 May 1863 — a strong same-scene, different-wording pair. The ward
# edition is by its own note "not a translation … but a complete re-write" — so the full/ pair is a demanding
# STRUCTURAL-divergence case (ward ~16% longer). Whole-novel witnesses exclude the differing front matter
# (title / redactor's note / TOC) via --no-collate-until, so only the novel body is collated.
mkdir -p journey-centre-earth journey-centre-earth/full
$CLEAN raw/pg3748.txt  journey-centre-earth/malleson.txt --from-marker '^CHAPTER I\.' --to-marker '^CHAPTER II\.'
# PG18857's body chapters are headed by their TITLE only (the '^CHAPTER N …' lines near the top are the TOC);
# excerpt between the Ch.1 and Ch.2 body titles.
$CLEAN raw/pg18857.txt journey-centre-earth/ward.txt     --from-marker '^MY UNCLE MAKES A GREAT DISCOVERY$' --to-marker '^THE MYSTERIOUS PARCHMENT$'
$CLEAN raw/pg3748.txt  journey-centre-earth/full/malleson.txt --no-collate-until '^CHAPTER I\.'
$CLEAN raw/pg18857.txt journey-centre-earth/full/ward.txt     --no-collate-until '^MY UNCLE MAKES A GREAT DISCOVERY$'

# WORK 4 — The Mysterious Island  [two English translations, Ch.1 'The Hurricane of 1865']
#   kingston = Agnes Kinloch Kingston translation (PG1268)
#   white    = Stephen W. White translation (PG8993)
# The full/ pair is the LARGEST real scale test in the corpus (~195k / 167k words). Front matter excluded.
mkdir -p mysterious-island mysterious-island/full
$CLEAN raw/pg1268.txt mysterious-island/kingston.txt --from-marker '^Chapter 1$'  --to-marker '^Chapter 2$'
$CLEAN raw/pg8993.txt mysterious-island/white.txt    --from-marker '^CHAPTER I\.' --to-marker '^CHAPTER II\.'
$CLEAN raw/pg1268.txt mysterious-island/full/kingston.txt --no-collate-until '^Chapter 1$'
$CLEAN raw/pg8993.txt mysterious-island/full/white.txt    --no-collate-until '^CHAPTER I\.'

# ---------------------------------------------------------------------------------------------------------------
# FRENCH WITNESSES (OPTIONAL — commented out; uncomment to build). The originals, for French<->English collation
# (needs a translation lexicon / peer-MSA strategy at collate time) or eventual French-French edition work. The
# cleaner preserves accents (verified 2026-07-24). Chapter markers were confirmed against the raw files:
#   pg38674 (De la terre à la lune):  'CHAPITRE PREMIER' .. 'CHAPITRE II'
#   pg14287 (L'île mystérieuse):      'CHAPITRE I' .. 'CHAPITRE II'
#   pg4791  (Voyage au centre…):      chapters are a bare roman numeral ('^I$'); has a Gallica FR+EN preface,
#                                     so exclude front matter with --no-collate-until '^I$' for the full witness.
# Sigla use an 'fr-' prefix so they never collide with the English witnesses in `--dir … --all`.
# mkdir -p earth-to-moon/fr mysterious-island/fr journey-centre-earth/fr 20000-leagues/fr
# $CLEAN raw/pg38674.txt earth-to-moon/fr/fr-original.txt        --from-marker '^CHAPITRE PREMIER$' --to-marker '^CHAPITRE II$'
# $CLEAN raw/pg14287.txt mysterious-island/fr/fr-original.txt    --from-marker '^CHAPITRE I$'       --to-marker '^CHAPITRE II$'
# $CLEAN raw/pg4791.txt  journey-centre-earth/fr/fr-original.txt --from-marker '^I$'                --to-marker '^II$'
# $CLEAN raw/pg5097.txt  20000-leagues/fr/fr-original.txt        # (find FR Part1/Ch1 markers first)
# Full French novels for scale (exclude front matter):
# $CLEAN raw/pg38674.txt earth-to-moon/fr/full-fr.txt        --no-collate-until '^CHAPITRE PREMIER$'
# $CLEAN raw/pg14287.txt mysterious-island/fr/full-fr.txt    --no-collate-until '^CHAPITRE I$'
# $CLEAN raw/pg4791.txt  journey-centre-earth/fr/full-fr.txt --no-collate-until '^I$'
# ---------------------------------------------------------------------------------------------------------------

echo "corpus built:" >&2
find 20000-leagues earth-to-moon journey-centre-earth mysterious-island -name '*.txt' | sort | while read -r f; do
  printf "  %-48s %6s words\n" "$f" "$(grep -oE '\w+' "$f" | wc -l | tr -d ' ')" >&2
done
