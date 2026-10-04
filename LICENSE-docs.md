# Documentation licence

Copyright (c) 2026 ancientlives and CollationKit contributors.

The CollationKit documentation is licensed under the
[Creative Commons Attribution 4.0 International licence (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/).
That covers everything under `docs/` and `site/`, and the Markdown files at the repository root.

You may share and adapt the documentation for any purpose, including commercially, provided you give
appropriate credit, link to the licence, and indicate if changes were made. The full legal code is at
<https://creativecommons.org/licenses/by/4.0/legalcode>.

## Exceptions

- **Source code**, including code embedded in documentation, is licensed under the [MIT licence](LICENSE).
- **Literary texts** in `corpus/verne/` and the literary excerpts in `docs/conformance/cases/` (works by Jules
  Verne and his translators, Mary Shelley, Walt Whitman and Alexander Pushkin) are in the public domain in the
  US, with the single exception below. They were obtained from [Project Gutenberg](https://www.gutenberg.org/)
  and the Internet Archive; the Project Gutenberg licence and trademark header has been removed. Provenance for
  each witness is recorded in its `meta.json`. None of these texts is covered by the MIT or CC BY licences.
- **Exception: the F. P. Walter translation** of *Twenty Thousand Leagues Under the Seas* (Project Gutenberg
  #2488) is **© 1999 Frederick Paul Walter** and is not in the public domain. It is not distributed in this
  repository except for one 87-word paragraph (the novel's opening), which appears as a witness in conformance
  cases 20, 22 and 29 (`walter.txt` / `en-walter.txt`), in the readings of their goldens, and in the published
  viewer demo built from case 29 (`site/demos/verne-trilingual.html`). It is quoted, with
  attribution, for scholarly research and testing only, and is excluded from every licence granted here. The
  full Walter witnesses used by the project can be rebuilt locally from your own Project Gutenberg download with
  `corpus/verne/scripts/build_corpus.sh`, subject to Project Gutenberg's licence.
- The machine-readable test fixtures (`docs/conformance/golden/`, `docs/conformance/collation.schema.json`) may
  also be used under the MIT licence, so ports of the engine can vendor them freely (the quoted Walter readings
  within them remain subject to the exception above).
