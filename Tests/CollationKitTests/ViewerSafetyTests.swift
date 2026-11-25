import XCTest
@testable import CollationKit
@testable import CollateCLI

// MARK: - Viewer safety and speed (release 1 review, blockers B11, B12, B15)
//
// B11: witness ids come from file names and were inserted into `innerHTML` unescaped in three places, so a file
// named `<img src=x onerror=…>.txt` ran script when the viewer opened; and placeholders were substituted one after
// another, so a witness named `%%DATA%%` pulled the whole payload into the page title. B12: the embedded JSON escaped
// only `</`, so witness text containing `<!--<script` switched the HTML parser into a state where the data script
// never closed and the page rendered blank. B15: `opacity` on every struck-through span in the Changes view made
// WebKit take about a minute to lay out a full novel.

final class ViewerSafetyTests: XCTestCase {

    private func html(_ witnesses: [Witness]) -> String {
        var opts = CLIOptions(explicitFiles: witnesses.map(\.id)); opts.format = .html
        return HTMLExport.html(CollationRunner.run(opts, witnesses: witnesses, includeViewerPairs: true))
    }

    private func dataBlock(_ page: String) -> String {
        page.components(separatedBy: "<script type=\"application/json\" id=\"data\">")[1]
            .components(separatedBy: "</script>")[0]
    }

    func testEmbeddedDataHasNoRawMarkupCharacters() {
        let page = html([Witness(id: "A", text: "text <!--<script here & there > \u{2028} end"),
                         Witness(id: "B", text: "text here and there end")])
        let data = dataBlock(page)
        for raw in ["<", ">", "&", "\u{2028}"] { XCTAssertFalse(data.contains(raw), "raw \(raw.debugDescription) in data") }
        // The escaped data still decodes to the original text.
        let decoded = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any]
        let texts = (decoded?["witnesses"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []
        XCTAssertTrue(texts.contains("text <!--<script here & there > \u{2028} end"))
    }

    func testAHostileWitnessIdIsNeverInsertedAsMarkup() {
        // The three places the page script built innerHTML from a witness id without `esc()` (other uses of `D.base`
        // assign to `textContent`, which is safe by construction).
        let script = HTMLExport.template
        for unescaped in ["'<b>' + primaryMate", "innerHTML = capitalise(mate)", "+ D.base + ' and '"] {
            XCTAssertFalse(script.contains(unescaped), "unescaped id interpolation: \(unescaped)")
        }
        // And the title, the one server-side insertion, is HTML-escaped.
        let page = html([Witness(id: "<img src=x onerror=alert(1)>", text: "the red door"),
                         Witness(id: "B", text: "the blue door")])
        let title = page.components(separatedBy: "<title>")[1].components(separatedBy: "</title>")[0]
        XCTAssertFalse(title.contains("<img"))
        XCTAssertTrue(title.contains("&lt;img"))
    }

    func testPlaceholdersAreFilledInOnePass() {
        let page = html([Witness(id: "%%DATA%%", text: "the red door"), Witness(id: "B", text: "the blue door")])
        let title = page.components(separatedBy: "<title>")[1].components(separatedBy: "</title>")[0]
        XCTAssertTrue(title.contains("%%DATA%%"), "the witness name appears literally in the title")
        XCTAssertFalse(title.contains("\"witnesses\""), "the payload is not pulled into the title")
        XCTAssertEqual(HTMLExport.fillPlaceholders("a %%X%% b %%Y%% %%Z%% 100%% done", ["%%X%%": "%%Y%%", "%%Y%%": "y"]),
                       "a %%Y%% b y %%Z%% 100%% done", "values are not re-scanned; unknown and stray markers are kept")
    }

    func testTheChangesViewDoesNotUseOpacityOnItsSpans() {
        let rule = HTMLExport.template.components(separatedBy: "\n").first { $0.contains("#changes .sub-old {") } ?? ""
        XCTAssertFalse(rule.isEmpty)
        XCTAssertFalse(rule.contains("opacity"), "opacity on every span makes WebKit lay out a full novel very slowly")
    }
}
