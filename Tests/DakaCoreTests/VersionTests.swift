import XCTest
import DakaCore

final class VersionTests: XCTestCase {
    func testParseBasic() {
        XCTAssertEqual(AppVersion.parse("1.0.3"), AppVersion(major: 1, minor: 0, patch: 3))
    }

    func testParseWithVPrefix() {
        XCTAssertEqual(AppVersion.parse("v1.2.0"), AppVersion(major: 1, minor: 2, patch: 0))
        XCTAssertEqual(AppVersion.parse("V1.2.0"), AppVersion(major: 1, minor: 2, patch: 0))
    }

    func testParseMissingComponents() {
        XCTAssertEqual(AppVersion.parse("2"), AppVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(AppVersion.parse("2.5"), AppVersion(major: 2, minor: 5, patch: 0))
        XCTAssertEqual(AppVersion.parse("v3"), AppVersion(major: 3, minor: 0, patch: 0))
    }

    func testParseIgnoresPrereleaseSuffix() {
        XCTAssertEqual(AppVersion.parse("1.0.0-rc1"), AppVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(AppVersion.parse("v2.1.4-beta"), AppVersion(major: 2, minor: 1, patch: 4))
    }

    func testComparison() {
        XCTAssertTrue(AppVersion.parse("1.0.4")! > AppVersion.parse("1.0.3")!)
        XCTAssertTrue(AppVersion.parse("1.1.0")! > AppVersion.parse("1.0.9")!)
        XCTAssertTrue(AppVersion.parse("2.0.0")! > AppVersion.parse("1.9.9")!)
        XCTAssertFalse(AppVersion.parse("1.0.3")! > AppVersion.parse("1.0.3")!)
        XCTAssertTrue(AppVersion.parse("1.0.3")! < AppVersion.parse("1.0.4")!)
    }

    func testEqualityAndDescription() {
        XCTAssertEqual(AppVersion.parse("1.2.3"), AppVersion(major: 1, minor: 2, patch: 3))
        XCTAssertEqual(AppVersion(major: 1, minor: 2, patch: 3).description, "1.2.3")
    }

    func testInvalidReturnsNil() {
        XCTAssertNil(AppVersion.parse(""))
        XCTAssertNil(AppVersion.parse("abc"))
        XCTAssertNil(AppVersion.parse("v"))
    }
}
