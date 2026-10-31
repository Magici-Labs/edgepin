import XCTest
@testable import EdgePinCore

final class LayoutTests: XCTestCase {
    // A 1440x900 screen with a 25pt menu bar and no Dock.
    let v = CGRect(x: 0, y: 25, width: 1440, height: 875)

    func testStripsShareCornersWithTheSides() {
        let l = Layout(visible: v, thickness: [.left: 400, .top: 200])
        XCTAssertEqual(l.strip(.left), CGRect(x: 0, y: 25, width: 400, height: 875))
        XCTAssertEqual(l.strip(.top), CGRect(x: 400, y: 25, width: 1040, height: 200))
        XCTAssertEqual(l.free, CGRect(x: 400, y: 225, width: 1040, height: 675))
    }

    func testOverlappingWindowIsTrimmedOnOneSide() {
        let l = Layout(visible: v, thickness: [.left: 400])
        let w = CGRect(x: 100, y: 100, width: 900, height: 600)
        XCTAssertEqual(l.squeeze(w), CGRect(x: 400, y: 100, width: 600, height: 600))
    }

    func testWindowClearOfStripIsLeftAlone() {
        let l = Layout(visible: v, thickness: [.left: 400])
        let w = CGRect(x: 400, y: 100, width: 500, height: 500)
        XCTAssertFalse(l.overlaps(w))
        XCTAssertEqual(l.squeeze(w), w)
    }

    func testWindowMostlyInsideStripIsMovedOut() {
        let l = Layout(visible: v, thickness: [.right: 500])
        let w = CGRect(x: 1000, y: 100, width: 300, height: 400)
        XCTAssertEqual(l.squeeze(w), CGRect(x: 640, y: 100, width: 300, height: 400))
    }

    func testMaximizedWindowFillsWhatIsLeft() {
        let l = Layout(visible: v, thickness: [.left: 400, .bottom: 300])
        XCTAssertEqual(l.squeeze(v), l.free)
    }

    func testShiftOnlyKeepsSize() {
        let l = Layout(visible: v, thickness: [.left: 400])
        let w = CGRect(x: 100, y: 100, width: 900, height: 600)
        XCTAssertEqual(l.squeeze(w, shiftOnly: true), CGRect(x: 400, y: 100, width: 900, height: 600))
    }

    func testNearestEdgeIgnoresTheMenuBar() {
        // Flush under the menu bar but on the left half: left, not top.
        XCTAssertEqual(Layout.nearestEdge(of: CGRect(x: 20, y: 25, width: 600, height: 500), in: v), .left)
        XCTAssertEqual(Layout.nearestEdge(of: CGRect(x: 900, y: 200, width: 500, height: 600), in: v), .right)
        XCTAssertEqual(Layout.nearestEdge(of: CGRect(x: 200, y: 650, width: 1000, height: 250), in: v), .bottom)
    }

    func testInitialThickness() {
        XCTAssertEqual(Layout.initialThickness(of: CGRect(x: 0, y: 0, width: 500, height: 400), edge: .left, in: v), 500)
        XCTAssertEqual(Layout.initialThickness(of: CGRect(x: 0, y: 0, width: 1400, height: 400), edge: .left, in: v), 480)
        XCTAssertEqual(Layout.initialThickness(of: CGRect(x: 0, y: 0, width: 50, height: 400), edge: .left, in: v), 120)
    }

    func testOffsetFromEdge() {
        let w = CGRect(x: 1040, y: 25, width: 400, height: 875)
        XCTAssertEqual(Layout.offset(of: w, from: .right, in: v), 0)
        XCTAssertEqual(Layout.offset(of: w.offsetBy(dx: -100, dy: 0), from: .right, in: v), 100)
    }
}
