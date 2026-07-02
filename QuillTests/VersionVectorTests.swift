import XCTest
@testable import Quill

final class VersionVectorTests: XCTestCase {

    func testDominance() {
        XCTAssertTrue(VV.strictlyDominates(["a": 2], ["a": 1]))
        XCTAssertTrue(VV.strictlyDominates(["a": 1, "b": 1], ["a": 1]))
        XCTAssertFalse(VV.strictlyDominates(["a": 1], ["a": 1]))
    }

    func testEqualityTreatsMissingAsZero() {
        XCTAssertTrue(VV.equal(["a": 1, "b": 0], ["a": 1]))
        XCTAssertTrue(VV.equal([:], [:]))
        XCTAssertFalse(VV.equal(["a": 1], ["a": 2]))
    }

    func testConcurrent() {
        XCTAssertTrue(VV.concurrent(["a": 1], ["b": 1]))
        XCTAssertTrue(VV.concurrent(["a": 2, "b": 1], ["a": 1, "b": 2]))
        XCTAssertFalse(VV.concurrent(["a": 2], ["a": 1]))       // dominance, not concurrent
        XCTAssertFalse(VV.concurrent(["a": 1], ["a": 1]))       // equal, not concurrent
    }

    func testMergeTakesComponentwiseMax() {
        XCTAssertEqual(VV.merge(["a": 2, "b": 1], ["a": 1, "b": 3]), ["a": 2, "b": 3])
    }

    func testBumped() {
        XCTAssertEqual(VV.bumped(["a": 1], "a"), ["a": 2])
        XCTAssertEqual(VV.bumped(["a": 1], "b"), ["a": 1, "b": 1])
    }
}
