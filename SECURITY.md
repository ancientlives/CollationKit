# Security policy

## Reporting a vulnerability

Please report security problems **privately**, not in a public issue.

- Use GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a
  vulnerability**.
- If that option isn't available, contact the maintainer, [@ancientlives](https://github.com/ancientlives), and ask for
  a private channel without including the details.

You can expect an acknowledgement within a week. Please allow time for a fix before any public disclosure.

## Scope

CollationKit is a library and command-line tool that reads text files you give it. The parts most relevant to
security are:

- **The HTML viewer** (`collation.html`). It embeds the witnesses' text and file names in a self-contained page that
  people open in a browser and share. Any way for witness content or a file name to run script in that page is a
  vulnerability. (The page loads nothing from the network.)
- **File handling in the CLI**: reading witnesses and lexicons, and writing to the output folder.

The engine itself (`Sources/CollationKit`) performs no I/O.

## Supported versions

Security fixes are made on `main` and released in the next version. Until 1.0, only the latest release is supported.
