import XCTest
@testable import AXExporter

final class AXNodeTests: XCTestCase {

    func testSnapshotRoundTripsThroughJSON() throws {
        let node = AXNode(
            label: "Send", value: nil, hint: "Double tap to send",
            identifier: "send.button", traits: ["button"], isElement: true,
            frame: [10, 20, 100, 44], voiceOver: "Send, button, Double tap to send",
            children: []
        )
        let snapshot = AXSnapshot(appName: "JazariOneDev", screenSize: [393, 852], roots: [node])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AXSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.roots.first?.traits, ["button"])
    }
}
