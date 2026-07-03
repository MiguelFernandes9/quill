import XCTest
import PencilKit
@testable import Quill

final class StrokeEditTests: XCTestCase {

    /// A straight pen stroke from `start` to `end`.
    private func stroke(from start: CGPoint, to end: CGPoint) -> PKStroke {
        let points = (0...10).map { step -> PKStrokePoint in
            let t = CGFloat(step) / 10
            let location = CGPoint(x: start.x + (end.x - start.x) * t,
                                   y: start.y + (end.y - start.y) * t)
            return PKStrokePoint(location: location, timeOffset: TimeInterval(t),
                                 size: CGSize(width: 4, height: 4), opacity: 1,
                                 force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
                        path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    private func drawing() -> PKDrawing {
        PKDrawing(strokes: [
            stroke(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0)),      // 0: top
            stroke(from: CGPoint(x: 0, y: 200), to: CGPoint(x: 100, y: 200)),  // 1: far below
        ])
    }

    // MARK: - Hit-testing

    func testTapOnStrokeHits() {
        let hits = StrokeEdit.strokes(in: drawing(), near: CGPoint(x: 50, y: 3))
        XCTAssertEqual(hits, IndexSet([0]))
    }

    func testTapBetweenStrokesMissesBoth() {
        let hits = StrokeEdit.strokes(in: drawing(), near: CGPoint(x: 50, y: 100))
        XCTAssertTrue(hits.isEmpty)
    }

    func testTapBeyondRadiusMisses() {
        let hits = StrokeEdit.strokes(in: drawing(), near: CGPoint(x: 50, y: 40), radius: 10)
        XCTAssertTrue(hits.isEmpty)
    }

    func testHitRespectsStrokeTransform() {
        // Stroke 0 moved down by 500 — a tap at its OLD position must miss,
        // at its new position must hit.
        let moved = StrokeEdit.translate(drawing(), indices: IndexSet([0]), dx: 0, dy: 500)
        XCTAssertTrue(StrokeEdit.strokes(in: moved, near: CGPoint(x: 50, y: 3)).isEmpty)
        XCTAssertEqual(StrokeEdit.strokes(in: moved, near: CGPoint(x: 50, y: 503)), IndexSet([0]))
    }

    // MARK: - Bounds

    func testBoundsUnionsSelection() {
        let box = StrokeEdit.bounds(of: IndexSet([0, 1]), in: drawing())
        XCTAssertLessThanOrEqual(box.minY, 2)
        XCTAssertGreaterThanOrEqual(box.maxY, 198)
    }

    func testBoundsOfNothingIsNull() {
        XCTAssertTrue(StrokeEdit.bounds(of: IndexSet(), in: drawing()).isNull)
    }

    // MARK: - Edits

    func testTranslateMovesOnlySelection() {
        let moved = StrokeEdit.translate(drawing(), indices: IndexSet([0]), dx: 10, dy: 20)
        let movedBounds = moved.strokes[0].renderBounds
        let untouched = moved.strokes[1].renderBounds
        XCTAssertEqual(movedBounds.midY, drawing().strokes[0].renderBounds.midY + 20,
                       accuracy: 1)
        XCTAssertEqual(untouched.midY, drawing().strokes[1].renderBounds.midY, accuracy: 1)
    }

    func testDeleteRemovesOnlySelection() {
        let result = StrokeEdit.delete(drawing(), indices: IndexSet([0]))
        XCTAssertEqual(result.strokes.count, 1)
        XCTAssertEqual(result.strokes[0].renderBounds.midY,
                       drawing().strokes[1].renderBounds.midY, accuracy: 1)
    }

    func testDuplicateAppendsOffsetCopies() {
        let result = StrokeEdit.duplicate(drawing(), indices: IndexSet([0]))
        XCTAssertEqual(result.strokes.count, 3)
        // Copy appended at the END (rides the append-delta sync path).
        XCTAssertEqual(result.strokes[2].renderBounds.midY,
                       drawing().strokes[0].renderBounds.midY + 16, accuracy: 1)
    }

    func testOutOfRangeIndicesAreIgnored() {
        let result = StrokeEdit.delete(drawing(), indices: IndexSet([7]))
        XCTAssertEqual(result.strokes.count, 2)
        XCTAssertEqual(StrokeEdit.duplicate(drawing(), indices: IndexSet([9])).strokes.count, 2)
    }
}
