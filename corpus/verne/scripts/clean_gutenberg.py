#!/usr/bin/env python3
"""clean_gutenberg.py — turn a raw Project Gutenberg plain-text file into a clean collation witness.

Purpose
-------
Prepare English-translation editions of Jules Verne's novels (and any other Gutenberg text) as *witnesses*
for the CollationKit engine + `collate` CLI. English Verne is always a TRANSLATION of the French original, so
"variant English editions" means different translations / different years / different regions of those
translations — each is one witness of the same underlying work.

What it does (each step is conservative and documented so the result is reviewable and reproducible):
  1. Decode as UTF-8 (Gutenberg's modern encoding), tolerant of stray bytes.
  2. Strip everything outside the Gutenberg START/END boundary markers (the licence, header, and footer).
  3. Drop producer/transcriber lines ("Produced by …", "Credits: …", "[Illustration]", etc.) that are not
     part of the author's text and would pollute a collation.
  4. Normalise line endings to \n and collapse >2 blank lines to a single blank line (paragraph boundary),
     while PRESERVING paragraph breaks (the engine uses blank lines for paragraph structure).
  5. Optionally extract a chapter/section range by regex, so we can prepare comparable EXCERPTS across
     editions (e.g. "Chapter I" of each translation) as well as whole novels.
  6. Optionally strip a leading front-matter block (title page / contents) up to the first chapter heading.

It deliberately does NOT change spelling, punctuation, or wording — those are exactly the variants the engine
must see. Substantive/accidental folding is the ENGINE's job (its normaliser), not the cleaner's.

Usage
-----
  clean_gutenberg.py RAW.txt OUT.txt [options]

Options
  --from-marker "REGEX"   start the kept text at the first line matching REGEX (e.g. a chapter heading)
  --to-marker   "REGEX"   end the kept text before the first line (after --from) matching REGEX
  --no-collate-until "REGEX"  wrap everything BEFORE the first line matching REGEX in a `<!-- no_collate --> …
                          -->` region, so per-edition front matter (title page, redactor's/transcriber notes,
                          table of contents) is EXCLUDED from collation (the engine emits no tokens for it) but
                          kept in the file for display. Use for whole-novel witnesses whose front matter differs
                          between editions and would otherwise generate junk variants + skew the alignment. The
                          matching line (the first chapter/body heading) and everything after are collated.
  --keep-notes            do NOT drop producer/transcriber/illustration lines (default: drop them)
  --title "..."           OPTIONAL human-review title, written as a `<!-- … -->` comment at the top. OFF by
                          default because it would be tokenised as ordinary WORDS (the engine only treats the
                          exact marker `<!-- page break -->` specially), creating spurious variants. Keep
                          provenance in meta.json instead; use --title only for scratch/review copies.
  --quiet                 suppress the per-step summary on stderr

Examples
  # Whole book, boundaries + notes cleaned:
  clean_gutenberg.py raw/pg164.txt work/20kL-mercier.full.txt --title "20,000 Leagues (Mercier)"
  # Just Chapter 1, between two headings:
  clean_gutenberg.py raw/pg164.txt work/20kL-mercier.ch1.txt \
      --from-marker "^CHAPTER I\b" --to-marker "^CHAPTER II\b"

The cleaned file is a plain witness the `collate` CLI reads directly (its id is the filename stem). See
corpus/verne/README.md for the end-to-end process and how to add a new novel.
"""
from __future__ import annotations
import argparse, re, sys

# Gutenberg boundary markers (both the modern and a few legacy phrasings).
START_RE = re.compile(r"\*\*\*\s*START OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*", re.IGNORECASE)
END_RE   = re.compile(r"\*\*\*\s*END OF (THE|THIS) PROJECT GUTENBERG.*?\*\*\*", re.IGNORECASE)

# Lines that are production apparatus, not the author's text.
NOTE_RE = re.compile(
    r"^\s*(\[?Illustration.*?\]?|Produced by .*|Credits:.*|Transcriber'?s? Note.*|"
    r"E-?text prepared by .*|Updated:.*|Release Date:.*|Language:.*|Character set encoding:.*)\s*$",
    re.IGNORECASE,
)


def strip_boundaries(text: str) -> str:
    """Keep only the text between the START and END Gutenberg markers (inclusive of neither)."""
    start = START_RE.search(text)
    end = END_RE.search(text)
    s = start.end() if start else 0
    e = end.start() if end else len(text)
    return text[s:e]


def drop_notes(lines: list[str]) -> list[str]:
    return [ln for ln in lines if not NOTE_RE.match(ln)]


def normalise_blanks(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    # Collapse runs of 3+ newlines to exactly two (one blank line = a paragraph break the engine reads).
    text = re.sub(r"\n{3,}", "\n\n", text)
    # Trim trailing spaces on each line.
    text = re.sub(r"[ \t]+\n", "\n", text)
    return text.strip() + "\n"


def wrap_no_collate(text: str, until: str) -> str:
    """Wrap everything before the first line matching `until` in a `<!-- no_collate --> … -->` region.

    The engine (Tokenizer) skips a no_collate region entirely — no tokens, so it never reaches the aligner —
    while the text stays in the file for display. This excludes per-edition front matter (title / redactor's
    note / TOC) from a whole-novel collation, where it would otherwise be force-aligned into junk variants.
    """
    pat = re.compile(until)
    lines = text.split("\n")
    body_i = None
    for i, ln in enumerate(lines):
        if pat.search(ln):
            body_i = i
            break
    if body_i is None or body_i == 0:
        return text                                   # nothing before the body, or the marker never matched
    front = "\n".join(lines[:body_i]).rstrip()
    rest = "\n".join(lines[body_i:])
    return "<!-- no_collate\n" + front + "\n-->\n\n" + rest


def extract_range(text: str, frm: str | None, to: str | None) -> str:
    if not frm and not to:
        return text
    lines = text.split("\n")
    start_i, end_i = 0, len(lines)
    if frm:
        pat = re.compile(frm)
        for i, ln in enumerate(lines):
            if pat.search(ln):
                start_i = i
                break
    if to:
        pat = re.compile(to)
        for i in range(start_i + 1, len(lines)):
            if pat.search(lines[i]):
                end_i = i
                break
    return "\n".join(lines[start_i:end_i])


def main() -> int:
    ap = argparse.ArgumentParser(description="Clean a raw Gutenberg text into a collation witness.")
    ap.add_argument("raw"); ap.add_argument("out")
    ap.add_argument("--from-marker", dest="frm", default=None)
    ap.add_argument("--to-marker", dest="to", default=None)
    ap.add_argument("--no-collate-until", dest="ncu", default=None)
    ap.add_argument("--keep-notes", action="store_true")
    ap.add_argument("--title", default=None)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    with open(a.raw, "r", encoding="utf-8", errors="replace") as f:
        raw = f.read()
    body = strip_boundaries(raw)
    body = extract_range(body, a.frm, a.to)
    lines = body.split("\n")
    if not a.keep_notes:
        lines = drop_notes(lines)
    cleaned = normalise_blanks("\n".join(lines))
    if a.ncu:
        cleaned = wrap_no_collate(cleaned, a.ncu)
    if a.title:
        cleaned = f"<!-- {a.title} -->\n\n" + cleaned

    with open(a.out, "w", encoding="utf-8") as f:
        f.write(cleaned)

    if not a.quiet:
        words = len(re.findall(r"\w+", cleaned))
        print(f"cleaned {a.raw} -> {a.out}  ({words:,} words, {cleaned.count(chr(10))+1} lines)",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
