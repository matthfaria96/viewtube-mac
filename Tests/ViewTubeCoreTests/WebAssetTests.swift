import XCTest
@testable import ViewTubeCore

final class WebAssetTests: XCTestCase {
    func testExpandsCssMarkerAsJsString() throws {
        let out = try WebAsset.expand("s.textContent = __VT_CSS(a-b.css)__;") { name in
            XCTAssertEqual(name, "a-b.css")
            return "p { content: \"x\"; }\n"
        }
        XCTAssertEqual(out, #"s.textContent = "p { content: \"x\"; }\n";"#)
    }

    func testIgnoresNamesThatCouldLeaveTheFolder() throws {
        let script = "__VT_CSS(../x.css)__ __VT_CSS(A.css)__"
        XCTAssertEqual(try WebAsset.expand(script) { _ in XCTFail("não devia ler"); return "" }, script)
    }

    func testMissingCssThrows() {
        XCTAssertThrowsError(try WebAsset.expand("__VT_CSS(nada.css)__") { throw WebAsset.Failure.missing($0) })
    }

    /// A pasta `web/` do repositório: tudo que o manifesto lista existe e expande sem marcador sobrando.
    func testSharedWebFolderIsComplete() throws {
        let web = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web")
        let read = { (name: String) throws -> String in
            try String(contentsOf: web.appendingPathComponent(name), encoding: .utf8)
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(read("manifest.json").utf8)) as! [String: Any]
        let files = (manifest["documentStart"] as! [String]) + (manifest["documentEnd"] as! [String]) + [manifest["pageFlags"] as! String]
        XCTAssertEqual(files.count, 15)
        for file in files {
            let script = try WebAsset.expand(read(file), css: read)
            XCTAssertFalse(script.contains("__VT_CSS("), file)
            XCTAssertFalse(script.isEmpty, file)
        }
    }
}
