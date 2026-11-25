# Input format guide

How to prepare texts for CollationKit: witness files, page breaks, excluded regions, and translation lexicons.
The normative rules are in [`../reference/ALGORITHMS.md`](../reference/ALGORITHMS.md) §2.

## Witness files

- **One file per witness**, plain text in **UTF-8**. `collate` discovers `.txt` and `.md` files in a folder
  (`--dir`), or takes the files you name.
- **The witness id (siglum) is the file name without its extension**: `MS.txt` is witness `MS`. Ids must be unique,
  so `e1818/text.txt` and `e1831/text.txt` cannot be collated together; rename one of them.
- **The first witness is the base** (the copy-text) unless you choose another with `--base`.
- Keep the file to **the text alone**. A title or provenance line is collated as words. Record provenance elsewhere
  (the conformance cases and the Verne corpus use a `meta.json` beside the texts).
- Line endings may be LF or CRLF.

## What counts as a word

- A **word** starts with a letter, digit or mark and may contain apostrophes and hyphens *between* word characters
  (`don't`, `dun-white`). Any script works, including characters above U+FFFF.
- Everything else that isn't whitespace is **punctuation**: quotation marks, a dash (`--` or `—`), a leading or closing
  apostrophe, symbols and emoji.
- In the default **substantive** comparison, punctuation, case, accents, typographic vs straight apostrophes, and
  hyphenation (`dun-white` vs `dun white`) are folded away, so only changes of wording are reported. Use
  `--diplomatic` to treat every one of those differences as a variant.
- Scripts written without spaces between words (Chinese, Japanese, Thai) are **not yet segmented**: a whole sentence
  becomes one token (backlog item B6).

## Pages and citations

Citations take the form `p.2 · line 4 · word 3`. Lines count **text lines only**: blank lines are not numbered.

By default pages break at these markers, which are not collated themselves:

| Marker | Notes |
| --- | --- |
| A form feed (`\f`) | Common in typescripts and OCR output |
| `<!-- page break -->` | On its own or inline |
| A line containing only `---` | **Careful in Markdown:** a thematic break (horizontal rule) also starts a new page |

Alternatively, cite against a uniform printed page with `--lines-per-page N`, or number lines continuously with
`--through-numbered`. Both are **experimental**.

## Excluding matter that should not be collated

Front matter, a translator's preface or a list of illustrations usually differs completely between editions.
Collating it produces hundreds of meaningless variants and can disturb the alignment of the real text. Wrap it in a
`no_collate` region; the text is kept in the witness but produces no tokens.

One comment, with the excluded matter inside it:

```
<!-- no_collate
Title page, translator's note, contents…
-->
```

Or two comments, with ordinary text between them:

```
<!-- no_collate -->
Title page, translator's note, contents…
<!-- /no_collate -->
```

- `no-collate` is accepted too, and the markers are case-insensitive.
- Comments nested inside a one-comment region (such as `<!-- page break -->`) do not end it.
- Page-break markers inside a region are ignored.
- A region that is never closed runs to the end of the text.

## Translation lexicons (experimental)

For witnesses in different languages, `--lexicon file.lex` supplies groups of equivalent words, so translation pairs
can anchor the alignment. It affects alignment only: every witness's own words are still what the apparatus reports.

```
# français ↔ english
année, year
mer, sea, seas
marquée, marked, signalised
```

- One group per line; forms separated by commas; `#` starts a comment; blank lines are ignored.
- Write forms as they appear: they are normalised the same way as the texts, so `année` matches `Année` and `annee`.
- It works best with `--strategy peer-msa`. Cross-language alignment is still limited where word order differs, for
  example French noun–adjective vs English adjective–noun.

## Conformance cases

Each case in [`../conformance/cases/`](../conformance/cases/) is a folder of witness files plus a `meta.json` that
records the base, the witness order, the normaliser, the pagination, and optionally the strategy and an inline
lexicon. See [`../conformance/README.md`](../conformance/README.md).
