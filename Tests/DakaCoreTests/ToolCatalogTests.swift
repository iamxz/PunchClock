import XCTest
@testable import DakaCore

final class ToolCatalogTests: XCTestCase {
    func testAllToolsAreListed() {
        XCTAssertEqual(ToolCatalog.all.count, ToolID.allCases.count)
        XCTAssertEqual(ToolCatalog.all.map(\.id), ToolID.allCases)
    }

    func testMetadataLookup() {
        for id in ToolID.allCases {
            let meta = ToolCatalog.metadata(for: id)
            XCTAssertEqual(meta.id, id)
            XCTAssertFalse(meta.title.isEmpty)
            XCTAssertFalse(meta.symbol.isEmpty)
        }
        XCTAssertEqual(ToolCatalog.metadata(for: .punch).title, "打卡统计")
    }
}
