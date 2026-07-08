import XCTest
@testable import AXCore

final class AccessibilityReaderTests: XCTestCase {

    func testReadableStringFromString() {
        let value = "Send" as CFString
        XCTAssertEqual(AccessibilityReader.readableString(from: value), "Send")
    }

    func testEmptyStringBecomesNil() {
        let value = "" as CFString
        XCTAssertNil(AccessibilityReader.readableString(from: value))
    }

    func testReadableStringFromNumber() {
        let value = NSNumber(value: 42)
        XCTAssertEqual(AccessibilityReader.readableString(from: value), "42")
    }

    func testReadableStringFromBool() {
        XCTAssertEqual(AccessibilityReader.readableString(from: kCFBooleanTrue), "true")
        XCTAssertEqual(AccessibilityReader.readableString(from: kCFBooleanFalse), "false")
    }
}
