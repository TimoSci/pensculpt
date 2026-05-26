# Grow Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a tap+hold "grow selection" to `AppMode.select` that selects strokes by proximity from a stroke or a canvas point, with time-growing radius, density-adaptive speed (pauses at gaps between groups), and rich visualization (sphere, candidate pulse, golden pause halo). Coexists with lasso via gesture differentiation.

**Architecture:** Two phases. **Phase 1** is a behavior-preserving refactor: introduce `SelectionStrategy` marker protocol, move `LassoSelection` into `Drawing/Selection/` and rename it `LassoStrategy`. **Phase 2** adds `GrowStrategy` (algorithm + `GrowSession` driven by `CADisplayLink`), `DensityProbe` (computes radius increment to next candidate), `GrowthVisualization` (SwiftUI overlay), and renames `LassoOverlay` → `SelectionOverlay` with a `UILongPressGestureRecognizer` mutually exclusive with the existing pan.

**Tech Stack:** Swift, SwiftUI, UIKit (`UIViewRepresentable`, `UIGestureRecognizer`), `CADisplayLink`, XCTest. iOS 17+.

**Spec:** `docs/superpowers/specs/2026-05-08-grow-selection-design.md`

---

## File Structure

New directory: `PenSculpt/Drawing/Selection/`

| File | Purpose |
|------|---------|
| `PenSculpt/Drawing/Selection/SelectionStrategy.swift` | Marker protocol; namespace declaration |
| `PenSculpt/Drawing/Selection/LassoStrategy.swift` | Renamed from `LassoSelection.swift`. Conforms to `SelectionStrategy`. Same algorithm. |
| `PenSculpt/Drawing/Selection/GrowOrigin.swift` | Enum: `.stroke(UUID, CGPoint)` or `.point(CGPoint)` |
| `PenSculpt/Drawing/Selection/DensityProbe.swift` | Static helper: smallest radius increment to admit next stroke |
| `PenSculpt/Drawing/Selection/GrowStrategy.swift` | Algorithm + `GrowSession` (mutable state); produces `GrowFrame` per tick |
| `PenSculpt/Views/SelectionOverlay.swift` | Renamed from `LassoOverlay.swift`. Adds long-press recognizer. |
| `PenSculpt/Views/GrowthVisualization.swift` | SwiftUI view: sphere outline + candidate pulse + golden halo |

Modifications:

- `PenSculpt/Views/DrawingViewModel.swift` — add `growSession`, `growthState`, handlers, display-link controller
- `PenSculpt/Views/DrawingScreen.swift` — `LassoOverlay` → `SelectionOverlay`; add `GrowthVisualization` layer
- `PenSculpt/Views/Tooltips/TooltipID.swift` — update `modeToggle` subtitle

Tests (new directory `PenSculptTests/Selection/`):

| File | Purpose |
|------|---------|
| `PenSculptTests/Selection/LassoStrategyTests.swift` | Replaces `LassoSelectionTests.swift` (algorithm tests only — coordinate tests remain in their own file) |
| `PenSculptTests/Selection/DensityProbeTests.swift` | Min-radius-to-next computation |
| `PenSculptTests/Selection/GrowStrategyTests.swift` | Algorithm: start, tick, finalize, monotonic, pause |
| `PenSculptTests/Selection/GrowOriginTests.swift` | Equality, conversion helpers |
| `PenSculptTests/SelectionOverlayTests.swift` | Replaces `LassoViewTests.swift`, plus long-press scenarios |
| `PenSculptTests/DrawingViewModelTests.swift` | Add tests for grow session lifecycle |

Files renamed/deleted:

- `PenSculpt/Drawing/LassoSelection.swift` → `PenSculpt/Drawing/Selection/LassoStrategy.swift` (renamed)
- `PenSculpt/Views/LassoOverlay.swift` → `PenSculpt/Views/SelectionOverlay.swift` (renamed)
- `PenSculptTests/LassoSelectionTests.swift` → split: algorithm parts move to `PenSculptTests/Selection/LassoStrategyTests.swift`; coordinate-conversion parts stay (rename file accordingly — see Task 1)

---

## Tunable constants (record in code)

These live as `static let` at the top of `GrowStrategy.swift`. Iterate during manual testing.

| Constant | Initial value | Meaning |
|----------|---------------|---------|
| `baseGrowthSpeed` | `50.0` | Pixels per second of radius growth (canvas coords) |
| `densityPauseFactor` | `0.1` | Speed multiplier during pause (0.1 = 10% of base) |
| `densityPauseThreshold` | `3.0` | If `requiredDeltaR / nominalDeltaR > this`, slow down |
| `initialRadius` | `8.0` | Radius at t=0 (so direct touch grabs nearby strokes) |
| `tickInterval` | `1/60.0` | Display-link tick step (logical) |

In `GrowthVisualization.swift`:

| Constant | Initial value | Meaning |
|----------|---------------|---------|
| `pulsePeriod` | `1.2` | Seconds per pulse cycle for candidate stroke |
| `haloColor` | `.systemYellow` (UIColor) | Pause halo color |
| `sphereStrokeColor` | `.systemBlue` (alpha 0.7) | Growth sphere outline color |

In `SelectionOverlay.swift`:

| Constant | Initial value | Meaning |
|----------|---------------|---------|
| `longPressMinimumDuration` | `0.15` | Seconds before grow gesture fires |
| `longPressAllowableMovement` | `5.0` | Points of jitter allowed before grow cancels in favor of lasso |

---

## Phase 1 — Refactor (no behavior change)

### Task 1: Introduce `SelectionStrategy` protocol; move and rename `LassoSelection`

**Files:**
- Create: `PenSculpt/Drawing/Selection/SelectionStrategy.swift`
- Move/rename: `PenSculpt/Drawing/LassoSelection.swift` → `PenSculpt/Drawing/Selection/LassoStrategy.swift`
- Modify: `PenSculpt/Views/DrawingViewModel.swift` (caller of `LassoSelection`)
- Modify: `PenSculpt/Views/DrawingScreen.swift` (no callers — verify)
- Move/split: `PenSculptTests/LassoSelectionTests.swift` → algorithm parts to `PenSculptTests/Selection/LassoStrategyTests.swift`; coordinate-conversion parts to `PenSculptTests/SelectionCoordinateTests.swift` (renamed-and-trimmed)

- [ ] **Step 1.1: Create directory and protocol file**

Create `PenSculpt/Drawing/Selection/SelectionStrategy.swift`:

```swift
import Foundation

/// Marker protocol for selection strategies. Each conforming type defines
/// its own input shape; consumers call concrete static APIs directly.
/// The protocol exists to document the family and to anchor future
/// shared APIs (e.g. logging, analytics) without forcing a single signature.
protocol SelectionStrategy {
    associatedtype Input
}
```

- [ ] **Step 1.2: Move and rename LassoSelection to LassoStrategy**

Delete `PenSculpt/Drawing/LassoSelection.swift`.

Create `PenSculpt/Drawing/Selection/LassoStrategy.swift`:

```swift
import Foundation

enum LassoStrategy: SelectionStrategy {
    typealias Input = [CGPoint]  // polygon

    /// Ray-casting point-in-polygon test.
    static func contains(_ point: CGPoint, in polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y),
               point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Returns true if at least `threshold` fraction of the stroke's points
    /// are inside the polygon (default 50%).
    static func isStrokeSelected(
        _ stroke: Stroke,
        by polygon: [CGPoint],
        threshold: CGFloat = 0.5
    ) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        let lassoBounds = boundingBox(of: polygon)
        guard stroke.boundingBox.intersects(lassoBounds) else { return false }
        let insideCount = stroke.points.filter { contains($0.location, in: polygon) }.count
        return CGFloat(insideCount) / CGFloat(stroke.points.count) >= threshold
    }

    /// Returns IDs of all strokes where ≥ threshold of points are inside the polygon.
    static func selectedStrokeIDs(
        strokes: [Stroke],
        polygon: [CGPoint],
        threshold: CGFloat = 0.5
    ) -> Set<UUID> {
        var ids = Set<UUID>()
        for stroke in strokes {
            if isStrokeSelected(stroke, by: polygon, threshold: threshold) {
                ids.insert(stroke.id)
            }
        }
        return ids
    }

    private static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

- [ ] **Step 1.3: Update caller in DrawingViewModel**

In `PenSculpt/Views/DrawingViewModel.swift`, change `LassoSelection.selectedStrokeIDs(...)` to `LassoStrategy.selectedStrokeIDs(...)`. The line currently around line 67 (`func handleLassoCompleted(polygon: [CGPoint])`).

- [ ] **Step 1.4: Move test file — algorithm tests**

Create `PenSculptTests/Selection/LassoStrategyTests.swift` with the algorithm tests (`testPointInPolygon`, `testStrokeSelectionThreshold`, `testPKStrokeLocationsPreservedAfterConversion`, `testLassoSelectsStrokeAtSameCoordinates`). Replace every `LassoSelection` reference with `LassoStrategy`. The other tests in the original file stay where they are for now (next step).

```swift
import XCTest
import PencilKit
@testable import PenSculpt

final class LassoStrategyTests: XCTestCase {

    func testPointInPolygon() {
        let square = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 0)
        ]
        XCTAssertTrue(LassoStrategy.contains(CGPoint(x: 50, y: 50), in: square))
        XCTAssertFalse(LassoStrategy.contains(CGPoint(x: 150, y: 50), in: square))
        XCTAssertFalse(LassoStrategy.contains(CGPoint(x: 50, y: 150), in: square))
    }

    func testStrokeSelectionThreshold() {
        let points = (0..<10).map {
            StrokePoint(location: CGPoint(x: CGFloat($0) * 10, y: 50),
                        pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        }
        let stroke = Stroke(points: points)

        let halfPolygon = [
            CGPoint(x: -1, y: 0), CGPoint(x: 46, y: 0),
            CGPoint(x: 46, y: 100), CGPoint(x: -1, y: 100), CGPoint(x: -1, y: 0)
        ]
        XCTAssertTrue(LassoStrategy.isStrokeSelected(stroke, by: halfPolygon))

        let smallPolygon = [
            CGPoint(x: -1, y: 0), CGPoint(x: 36, y: 0),
            CGPoint(x: 36, y: 100), CGPoint(x: -1, y: 100), CGPoint(x: -1, y: 0)
        ]
        XCTAssertFalse(LassoStrategy.isStrokeSelected(stroke, by: smallPolygon))
    }

    func testPKStrokeLocationsPreservedAfterConversion() {
        let inputLocation = CGPoint(x: 500, y: 700)
        let pkPoint = PKStrokePoint(location: inputLocation, timeOffset: 0,
                                     size: CGSize(width: 5, height: 5), opacity: 1,
                                     force: 1, azimuth: 0, altitude: .pi / 4)
        let path = PKStrokePath(controlPoints: [pkPoint], creationDate: Date())
        let pkStroke = PKStroke(ink: PKInk(.pen, color: .black), path: path)
        let stroke = StrokeConverter.convert(pkStroke)

        XCTAssertEqual(stroke.points[0].location.x, 500, accuracy: 1)
        XCTAssertEqual(stroke.points[0].location.y, 700, accuracy: 1)
    }

    func testLassoSelectsStrokeAtSameCoordinates() {
        let points = [
            StrokePoint(location: CGPoint(x: 500, y: 700), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 510, y: 710), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0.1)
        ]
        let stroke = Stroke(points: points)

        let polygon = [
            CGPoint(x: 450, y: 650), CGPoint(x: 550, y: 650),
            CGPoint(x: 550, y: 750), CGPoint(x: 450, y: 750), CGPoint(x: 450, y: 650)
        ]
        XCTAssertTrue(LassoStrategy.isStrokeSelected(stroke, by: polygon))
    }
}
```

- [ ] **Step 1.5: Move coordinate-conversion tests to their own file**

Create `PenSculptTests/SelectionCoordinateTests.swift` with `testSiblingViewsAtSameFrameHaveMatchingCoords`, `testConvertCorrectsBetweenOffsetViews`, `testPKCanvasViewContentInsets`, `testViewBridgeCoordinateConversion`, `testNoOffsetWhenViewsShareFrame`, `testFallbackWhenBridgeRefNil`. These tests reference `LassoView` — keep using `LassoView` for now; Task 7 will rename it to `SelectionView` and update this file.

Replace `LassoSelection` references in this file with `LassoStrategy`.

- [ ] **Step 1.6: Delete old test file**

Delete `PenSculptTests/LassoSelectionTests.swift`. All cases now live in the two files above.

- [ ] **Step 1.7: Run all tests, verify green**

Run: `xcodebuild test -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -30`

Expected: all tests pass. No behavior change.

- [ ] **Step 1.8: Commit**

```bash
git add -A
git commit -m "refactor(selection): introduce SelectionStrategy protocol, rename LassoSelection→LassoStrategy

Move selection code into PenSculpt/Drawing/Selection/. Pure rename; no behavior change.
Splits LassoSelectionTests into algorithm tests (LassoStrategyTests) and coordinate
tests (SelectionCoordinateTests).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Grow algorithm core

### Task 2: `GrowOrigin` enum + distance helpers

**Files:**
- Create: `PenSculpt/Drawing/Selection/GrowOrigin.swift`
- Create: `PenSculptTests/Selection/GrowOriginTests.swift`

- [ ] **Step 2.1: Write failing tests**

Create `PenSculptTests/Selection/GrowOriginTests.swift`:

```swift
import XCTest
@testable import PenSculpt

final class GrowOriginTests: XCTestCase {

    func testStrokeOriginExposesAnchorPoint() {
        let id = UUID()
        let origin = GrowOrigin.stroke(strokeID: id, anchor: CGPoint(x: 50, y: 50))
        XCTAssertEqual(origin.anchor, CGPoint(x: 50, y: 50))
    }

    func testPointOriginExposesAnchorPoint() {
        let origin = GrowOrigin.point(CGPoint(x: 100, y: 200))
        XCTAssertEqual(origin.anchor, CGPoint(x: 100, y: 200))
    }

    func testInitialStrokeIDForStrokeOrigin() {
        let id = UUID()
        let origin = GrowOrigin.stroke(strokeID: id, anchor: .zero)
        XCTAssertEqual(origin.initialStrokeID, id)
    }

    func testInitialStrokeIDNilForPointOrigin() {
        XCTAssertNil(GrowOrigin.point(.zero).initialStrokeID)
    }
}
```

Run: `xcodebuild test -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/GrowOriginTests 2>&1 | tail -10`

Expected: FAIL — `GrowOrigin` undefined.

- [ ] **Step 2.2: Implement `GrowOrigin`**

Create `PenSculpt/Drawing/Selection/GrowOrigin.swift`:

```swift
import Foundation

/// Where a grow-selection begins.
/// `.stroke` — user tapped on top of an existing stroke; that stroke seeds the selection.
/// `.point` — user tapped on empty canvas; a virtual sphere expands from `anchor`.
enum GrowOrigin: Equatable {
    case stroke(strokeID: UUID, anchor: CGPoint)
    case point(CGPoint)

    var anchor: CGPoint {
        switch self {
        case .stroke(_, let anchor): return anchor
        case .point(let p):          return p
        }
    }

    var initialStrokeID: UUID? {
        switch self {
        case .stroke(let id, _): return id
        case .point:             return nil
        }
    }
}
```

- [ ] **Step 2.3: Run tests, expect green**

Run: `xcodebuild test ... -only-testing:PenSculptTests/GrowOriginTests`. Expected: PASS.

- [ ] **Step 2.4: Commit**

```bash
git add PenSculpt/Drawing/Selection/GrowOrigin.swift PenSculptTests/Selection/GrowOriginTests.swift
git commit -m "feat(grow-selection): add GrowOrigin enum"
```

---

### Task 3: `DensityProbe` — minimum radius increment to next candidate

**Files:**
- Create: `PenSculpt/Drawing/Selection/DensityProbe.swift`
- Create: `PenSculptTests/Selection/DensityProbeTests.swift`

`DensityProbe` answers: given the current selection frontier and a set of candidate strokes, what is the smallest radius increment Δr that would admit at least one new stroke?

The "frontier" is a set of `CGPoint` samples (origin point + all sample points of currently-selected strokes). For each candidate stroke, the minimum distance from any of its sample points to any frontier point is its inclusion radius. The smallest such inclusion radius across all candidates is the answer.

Naive O(F × C × P) is fine for first version.

- [ ] **Step 3.1: Write failing tests**

Create `PenSculptTests/Selection/DensityProbeTests.swift`:

```swift
import XCTest
@testable import PenSculpt

final class DensityProbeTests: XCTestCase {

    private func stroke(at points: [CGPoint], id: UUID = UUID()) -> Stroke {
        let sps = points.map {
            StrokePoint(location: $0, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        }
        return Stroke(id: id, points: sps)
    }

    func testReturnsNilWhenNoCandidates() {
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [CGPoint(x: 0, y: 0)],
            candidates: []
        )
        XCTAssertNil(result)
    }

    func testReturnsDistanceMinusRadiusForSingleCandidate() {
        // Frontier at origin; candidate at (50, 0); current radius 10.
        // Distance is 50, so deltaR needed = 50 - 10 = 40.
        let candidate = stroke(at: [CGPoint(x: 50, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [.zero],
            candidates: [candidate]
        )
        XCTAssertEqual(result ?? 0, 40, accuracy: 0.01)
    }

    func testReturnsZeroWhenCandidateAlreadyWithinRadius() {
        // Candidate distance < current radius → delta is 0 (clamped, not negative).
        let candidate = stroke(at: [CGPoint(x: 5, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [.zero],
            candidates: [candidate]
        )
        XCTAssertEqual(result ?? -1, 0, accuracy: 0.01)
    }

    func testReturnsNearestCandidateAcrossMany() {
        // Three candidates at distances 80, 30, 200; nearest = 30; radius 10 → delta 20.
        let near = stroke(at: [CGPoint(x: 30, y: 0)])
        let mid  = stroke(at: [CGPoint(x: 80, y: 0)])
        let far  = stroke(at: [CGPoint(x: 200, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 10,
            frontier: [.zero],
            candidates: [far, near, mid]
        )
        XCTAssertEqual(result ?? 0, 20, accuracy: 0.01)
    }

    func testUsesNearestPointOfMultipointStroke() {
        // Stroke spans (40,0)→(20,0)→(60,0); nearest point is (20,0).
        let s = stroke(at: [CGPoint(x: 40, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 60, y: 0)])
        let result = DensityProbe.minimumDeltaR(
            currentRadius: 0,
            frontier: [.zero],
            candidates: [s]
        )
        XCTAssertEqual(result ?? 0, 20, accuracy: 0.01)
    }
}
```

Run: `xcodebuild test ... -only-testing:PenSculptTests/DensityProbeTests`. Expected: FAIL — `DensityProbe` undefined.

- [ ] **Step 3.2: Implement `DensityProbe`**

Create `PenSculpt/Drawing/Selection/DensityProbe.swift`:

```swift
import Foundation

enum DensityProbe {
    /// Smallest extra radius needed to admit at least one new stroke.
    /// Returns `nil` when there are no candidates. Returns `0` when at least one
    /// candidate is already within `currentRadius` of the frontier (clamped).
    static func minimumDeltaR(
        currentRadius: CGFloat,
        frontier: [CGPoint],
        candidates: [Stroke]
    ) -> CGFloat? {
        guard !candidates.isEmpty else { return nil }

        var bestDistance = CGFloat.infinity
        for candidate in candidates {
            for sp in candidate.points {
                for fp in frontier {
                    let d = hypot(sp.location.x - fp.x, sp.location.y - fp.y)
                    if d < bestDistance { bestDistance = d }
                }
            }
        }

        return max(0, bestDistance - currentRadius)
    }
}
```

- [ ] **Step 3.3: Run tests, expect green**

Run: `xcodebuild test ... -only-testing:PenSculptTests/DensityProbeTests`. Expected: all 5 PASS.

- [ ] **Step 3.4: Commit**

```bash
git add PenSculpt/Drawing/Selection/DensityProbe.swift PenSculptTests/Selection/DensityProbeTests.swift
git commit -m "feat(grow-selection): add DensityProbe for nearest-candidate distance"
```

---

### Task 4: `GrowStrategy` + `GrowSession`

`GrowStrategy` is a namespace with the tunable constants and entry points. `GrowSession` is a class that holds mutable per-tick state.

Each `tick(deltaTime:)` returns a `GrowFrame` describing the current visualization-relevant state.

**Files:**
- Create: `PenSculpt/Drawing/Selection/GrowStrategy.swift`
- Create: `PenSculptTests/Selection/GrowStrategyTests.swift`

- [ ] **Step 4.1: Write failing tests (start + initial inclusion)**

Create `PenSculptTests/Selection/GrowStrategyTests.swift`:

```swift
import XCTest
@testable import PenSculpt

final class GrowStrategyTests: XCTestCase {

    private func stroke(at points: [CGPoint], id: UUID = UUID()) -> Stroke {
        let sps = points.map {
            StrokePoint(location: $0, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        }
        return Stroke(id: id, points: sps)
    }

    private func canvas(_ strokes: [Stroke]) -> Canvas {
        var c = Canvas()
        c.strokes = strokes
        return c
    }

    // MARK: start

    func testStrokeOriginIncludesItselfAtT0() {
        let id = UUID()
        let seed = stroke(at: [CGPoint(x: 100, y: 100)], id: id)
        let other = stroke(at: [CGPoint(x: 500, y: 500)])
        let session = GrowStrategy.start(
            origin: .stroke(strokeID: id, anchor: CGPoint(x: 100, y: 100)),
            canvas: canvas([seed, other])
        )
        XCTAssertTrue(session.includedStrokeIDs.contains(id))
        XCTAssertFalse(session.includedStrokeIDs.contains(other.id))
    }

    func testPointOriginIncludesNothingAtT0WhenNoStrokeWithinInitialRadius() {
        let far = stroke(at: [CGPoint(x: 500, y: 500)])
        let session = GrowStrategy.start(
            origin: .point(.zero),
            canvas: canvas([far])
        )
        XCTAssertTrue(session.includedStrokeIDs.isEmpty)
    }

    func testPointOriginIncludesStrokeWithinInitialRadius() {
        // initialRadius = 8 → strokes within 8 of origin enter immediately.
        let close = stroke(at: [CGPoint(x: 5, y: 0)])
        let session = GrowStrategy.start(
            origin: .point(.zero),
            canvas: canvas([close])
        )
        XCTAssertTrue(session.includedStrokeIDs.contains(close.id))
    }

    // MARK: tick — monotonic radius

    func testRadiusGrowsMonotonically() {
        let s = stroke(at: [CGPoint(x: 1000, y: 1000)])
        let session = GrowStrategy.start(origin: .point(.zero), canvas: canvas([s]))
        var lastR = session.currentRadius
        for _ in 0..<10 {
            let frame = session.tick(deltaTime: 1.0 / 60.0)
            XCTAssertGreaterThanOrEqual(frame.radius, lastR)
            lastR = frame.radius
        }
    }

    // MARK: tick — admits strokes within radius

    func testTickIncludesCloseStrokeAfterEnoughTime() {
        // Stroke at distance 40; baseGrowthSpeed=50 px/s → reaches in ~0.64s.
        let target = stroke(at: [CGPoint(x: 40, y: 0)])
        let session = GrowStrategy.start(origin: .point(.zero), canvas: canvas([target]))
        let totalTime: TimeInterval = 1.0  // give it enough margin
        var t: TimeInterval = 0
        let dt = 1.0 / 60.0
        while t < totalTime {
            _ = session.tick(deltaTime: dt)
            t += dt
        }
        XCTAssertTrue(session.includedStrokeIDs.contains(target.id))
    }

    // MARK: pause behavior

    func testPauseTriggersWhenNextStrokeIsFar() {
        // Tight cluster near origin (immediate inclusion), then a big gap, then an isolated stroke.
        let cluster = (0..<3).map { i in
            stroke(at: [CGPoint(x: CGFloat(i) * 5, y: 0)])
        }
        let isolated = stroke(at: [CGPoint(x: 500, y: 0)])
        let session = GrowStrategy.start(
            origin: .point(.zero),
            canvas: canvas(cluster + [isolated])
        )
        // After cluster inclusion, density factor should drop below 1.0 within a few ticks.
        var sawPause = false
        for _ in 0..<10 {
            let frame = session.tick(deltaTime: 1.0 / 60.0)
            if frame.isPaused { sawPause = true; break }
        }
        XCTAssertTrue(sawPause, "Expected pause when the only remaining candidate is far away")
    }

    // MARK: finalize

    func testFinalizeReturnsCurrentlyIncludedSet() {
        let id = UUID()
        let seed = stroke(at: [CGPoint(x: 0, y: 0)], id: id)
        let session = GrowStrategy.start(
            origin: .stroke(strokeID: id, anchor: .zero),
            canvas: canvas([seed])
        )
        XCTAssertEqual(session.finalize(), [id])
    }

    func testFinalizeIsIdempotent() {
        let id = UUID()
        let seed = stroke(at: [CGPoint(x: 0, y: 0)], id: id)
        let session = GrowStrategy.start(
            origin: .stroke(strokeID: id, anchor: .zero),
            canvas: canvas([seed])
        )
        XCTAssertEqual(session.finalize(), session.finalize())
    }
}
```

Run: `xcodebuild test ... -only-testing:PenSculptTests/GrowStrategyTests`. Expected: FAIL — types undefined.

- [ ] **Step 4.2: Implement `GrowStrategy` and `GrowSession`**

Create `PenSculpt/Drawing/Selection/GrowStrategy.swift`:

```swift
import Foundation

/// One frame of grow-session state for visualization consumers.
struct GrowFrame {
    let radius: CGFloat
    let center: CGPoint
    let includedStrokeIDs: Set<UUID>
    let nextCandidateID: UUID?
    let isPaused: Bool
}

enum GrowStrategy: SelectionStrategy {
    typealias Input = GrowOrigin

    // MARK: Tunables (iterate during manual testing)
    static let baseGrowthSpeed: CGFloat = 50.0
    static let densityPauseFactor: CGFloat = 0.1
    static let densityPauseThreshold: CGFloat = 3.0
    static let initialRadius: CGFloat = 8.0

    /// Starts a new grow session, immediately admitting any strokes within `initialRadius`
    /// (and the seed stroke itself, if origin is `.stroke`).
    static func start(origin: GrowOrigin, canvas: Canvas) -> GrowSession {
        let session = GrowSession(origin: origin, allStrokes: canvas.strokes)
        session.admitInitial()
        return session
    }
}

/// Mutable per-hold state. Driven by `tick(deltaTime:)` from a display link.
final class GrowSession {
    let origin: GrowOrigin
    let allStrokes: [Stroke]

    private(set) var currentRadius: CGFloat = GrowStrategy.initialRadius
    private(set) var includedStrokeIDs: Set<UUID> = []
    private(set) var nextCandidateID: UUID?
    private(set) var isPaused: Bool = false

    init(origin: GrowOrigin, allStrokes: [Stroke]) {
        self.origin = origin
        self.allStrokes = allStrokes
    }

    /// Admit seed (for stroke origins) and any strokes already within `initialRadius`.
    func admitInitial() {
        if let seedID = origin.initialStrokeID {
            includedStrokeIDs.insert(seedID)
        }
        admitWithinRadius()
        recomputeNextCandidate()
    }

    /// Advances by `deltaTime` seconds. Updates radius (modulated by density), admits
    /// strokes inside the new radius, recomputes the next candidate and pause state.
    @discardableResult
    func tick(deltaTime: TimeInterval) -> GrowFrame {
        let nominalDeltaR = GrowStrategy.baseGrowthSpeed * CGFloat(deltaTime)
        let densityFactor = computeDensityFactor(nominalDeltaR: nominalDeltaR)
        let appliedDeltaR = nominalDeltaR * densityFactor
        currentRadius += appliedDeltaR
        admitWithinRadius()
        recomputeNextCandidate()
        isPaused = densityFactor < 0.5

        return GrowFrame(
            radius: currentRadius,
            center: origin.anchor,
            includedStrokeIDs: includedStrokeIDs,
            nextCandidateID: nextCandidateID,
            isPaused: isPaused
        )
    }

    /// Returns the final selection (snapshot of included strokes). Idempotent.
    func finalize() -> Set<UUID> {
        return includedStrokeIDs
    }

    // MARK: - Internals

    private var frontierPoints: [CGPoint] {
        var pts: [CGPoint] = [origin.anchor]
        for s in allStrokes where includedStrokeIDs.contains(s.id) {
            pts.append(contentsOf: s.points.map { $0.location })
        }
        return pts
    }

    private var candidateStrokes: [Stroke] {
        allStrokes.filter { !includedStrokeIDs.contains($0.id) }
    }

    private func admitWithinRadius() {
        let frontier = frontierPoints
        for stroke in candidateStrokes {
            for sp in stroke.points {
                var minD = CGFloat.infinity
                for fp in frontier {
                    let d = hypot(sp.location.x - fp.x, sp.location.y - fp.y)
                    if d < minD { minD = d }
                }
                if minD <= currentRadius {
                    includedStrokeIDs.insert(stroke.id)
                    break
                }
            }
        }
    }

    private func recomputeNextCandidate() {
        let frontier = frontierPoints
        var bestID: UUID?
        var bestD = CGFloat.infinity
        for stroke in candidateStrokes {
            for sp in stroke.points {
                for fp in frontier {
                    let d = hypot(sp.location.x - fp.x, sp.location.y - fp.y)
                    if d < bestD { bestD = d; bestID = stroke.id }
                }
            }
        }
        nextCandidateID = bestID
    }

    /// 1.0 = full speed; less = slowdown. Pause when next-stroke gap is much
    /// larger than what we'd cross in this tick at full speed.
    private func computeDensityFactor(nominalDeltaR: CGFloat) -> CGFloat {
        guard let deltaR = DensityProbe.minimumDeltaR(
            currentRadius: currentRadius,
            frontier: frontierPoints,
            candidates: candidateStrokes
        ), nominalDeltaR > 0 else {
            return 1.0
        }
        let ratio = deltaR / nominalDeltaR
        if ratio > GrowStrategy.densityPauseThreshold {
            return GrowStrategy.densityPauseFactor
        }
        return 1.0
    }
}
```

- [ ] **Step 4.3: Run tests, expect green**

Run: `xcodebuild test ... -only-testing:PenSculptTests/GrowStrategyTests`. Expected: all PASS.

If `testPauseTriggersWhenNextStrokeIsFar` fails, the cluster inclusion may take more than the allotted 10 ticks. Increase the loop to 60 ticks. If still failing, log `frame.isPaused` and `frame.includedStrokeIDs.count` per tick to diagnose.

- [ ] **Step 4.4: Commit**

```bash
git add PenSculpt/Drawing/Selection/GrowStrategy.swift PenSculptTests/Selection/GrowStrategyTests.swift
git commit -m "feat(grow-selection): add GrowStrategy + GrowSession with density-adaptive growth"
```

---

## Phase 3 — Visualization

### Task 5: `GrowthVisualization` overlay (UIViewRepresentable, mirrors SelectionHighlight)

Same structural pattern as `SelectionHighlight`: a `UIViewRepresentable` wrapping a custom `UIView` that converts canvas coords → its own coords via `canvasView.convert(_, to: self)`. A `CADisplayLink` inside the view drives the pulse animation independently of the grow tick.

It draws:
- Translucent filled circle (radius around `center`).
- Yellow halo when `isPaused`.
- Pulsing fill on the next-candidate stroke.

**Files:**
- Create: `PenSculpt/Views/GrowthVisualization.swift`

(No unit tests — view-only. Manual verification covers it.)

- [ ] **Step 5.1: Implement the view**

Create `PenSculpt/Views/GrowthVisualization.swift`:

```swift
import SwiftUI
import UIKit

struct GrowthVisualization: UIViewRepresentable {
    let frame: GrowFrame
    let allStrokes: [Stroke]
    var viewBridge: ViewBridge?

    static let pulsePeriod: CFTimeInterval = 1.2
    static let sphereStrokeColor = UIColor.systemBlue.withAlphaComponent(0.7)
    static let sphereFillColor = UIColor.systemBlue.withAlphaComponent(0.08)
    static let haloColor = UIColor.systemYellow.withAlphaComponent(0.85)
    static let candidatePeak = UIColor.systemBlue.withAlphaComponent(0.65)
    static let candidateBase = UIColor.systemBlue.withAlphaComponent(0.25)

    func makeUIView(context: Context) -> GrowthVisualizationView {
        let v = GrowthVisualizationView()
        v.backgroundColor = .clear
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: GrowthVisualizationView, context: Context) {
        uiView.frameModel = frame
        uiView.allStrokes = allStrokes
        uiView.canvasView = viewBridge?.canvasView
        uiView.setNeedsDisplay()
    }
}

final class GrowthVisualizationView: UIView {
    var frameModel: GrowFrame?
    var allStrokes: [Stroke] = []
    weak var canvasView: UIView?
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        startDisplayLink()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { displayLink?.invalidate() }

    private func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(animationTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func animationTick() { setNeedsDisplay() }

    override func draw(_ rect: CGRect) {
        guard let model = frameModel,
              let ctx = UIGraphicsGetCurrentContext() else { return }

        let center = convert(model.center)

        // Sphere fill
        ctx.setFillColor(GrowthVisualization.sphereFillColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - model.radius, y: center.y - model.radius,
                                    width: model.radius * 2, height: model.radius * 2))

        // Sphere outline (dashed)
        ctx.setStrokeColor(GrowthVisualization.sphereStrokeColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        ctx.strokeEllipse(in: CGRect(x: center.x - model.radius, y: center.y - model.radius,
                                      width: model.radius * 2, height: model.radius * 2))
        ctx.setLineDash(phase: 0, lengths: [])

        // Halo when paused
        if model.isPaused {
            let inset: CGFloat = 4
            let r = model.radius + inset
            ctx.setStrokeColor(GrowthVisualization.haloColor.cgColor)
            ctx.setLineWidth(3)
            ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r,
                                          width: r * 2, height: r * 2))
        }

        // Candidate pulse
        if let id = model.nextCandidateID,
           let stroke = allStrokes.first(where: { $0.id == id }),
           stroke.points.count > 1 {
            let now = CACurrentMediaTime()
            let phase = (sin((now / GrowthVisualization.pulsePeriod) * 2 * .pi) + 1) / 2
            let opacity = 0.25 + 0.4 * phase
            ctx.setStrokeColor(GrowthVisualization.candidateBase
                .withAlphaComponent(CGFloat(opacity)).cgColor)
            ctx.setLineWidth(6)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.beginPath()
            ctx.move(to: convert(stroke.points[0].location))
            for p in stroke.points.dropFirst() {
                ctx.addLine(to: convert(p.location))
            }
            ctx.strokePath()
        }
    }

    /// Canvas coords → this view's coords. Falls back to identity if no canvas attached.
    private func convert(_ canvasPoint: CGPoint) -> CGPoint {
        guard let canvas = canvasView else { return canvasPoint }
        return canvas.convert(canvasPoint, to: self)
    }
}
```

- [ ] **Step 5.2: Verify it compiles**

Run: `xcodebuild build -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -10`. Expected: BUILD SUCCEEDED.

- [ ] **Step 5.3: Commit**

```bash
git add PenSculpt/Views/GrowthVisualization.swift
git commit -m "feat(grow-selection): add GrowthVisualization overlay"
```

---

## Phase 4 — Gesture wiring

### Task 6: Rename `LassoOverlay` → `SelectionOverlay`; add long-press recognizer

**Files:**
- Move/rename: `PenSculpt/Views/LassoOverlay.swift` → `PenSculpt/Views/SelectionOverlay.swift`
- Move/rename: `PenSculptTests/LassoViewTests.swift` → `PenSculptTests/SelectionOverlayTests.swift` (and rewrite)
- Modify: `PenSculptTests/SelectionCoordinateTests.swift` (rename `LassoView` → `SelectionView`)

The renamed view exposes both `onLassoCompleted` (existing) and a new `onGrowGestureStarted(GrowOrigin)` callback. Internally it uses two recognizers:
- `UIPanGestureRecognizer` for lasso (existing touch flow rewritten as pan handler).
- `UILongPressGestureRecognizer` configured to require pan to fail.

`onLassoCompleted` keeps the same signature. The grow callback fires on `.began` of the long press (so the view model can start the session), then the overlay does **not** intercept further touches — the display link drives ticks until touchesEnded sends `onGrowGestureEnded`.

- [ ] **Step 6.1: Write/port test file (failing)**

Create `PenSculptTests/SelectionOverlayTests.swift`:

```swift
import XCTest
@testable import PenSculpt

final class SelectionOverlayTests: XCTestCase {

    // Lasso flow (ported from LassoViewTests)

    func testLassoBeginAndEndProducesPolygon() {
        let v = SelectionView()
        var captured: [CGPoint]?
        v.onLassoCompleted = { captured = $0 }

        v.beginStroke(displayPoint: CGPoint(x: 0, y: 0), targetPoint: CGPoint(x: 0, y: 0))
        v.continueStroke(displayPoint: CGPoint(x: 10, y: 0), targetPoint: CGPoint(x: 10, y: 0))
        v.continueStroke(displayPoint: CGPoint(x: 10, y: 10), targetPoint: CGPoint(x: 10, y: 10))
        v.endStroke()

        XCTAssertNotNil(captured)
        XCTAssertEqual(captured?.first, captured?.last, "polygon should be closed")
    }

    func testLassoTooShortDoesNotFireCallback() {
        let v = SelectionView()
        var fired = false
        v.onLassoCompleted = { _ in fired = true }
        v.beginStroke(displayPoint: .zero, targetPoint: .zero)
        v.endStroke()
        XCTAssertFalse(fired)
    }

    // Grow flow (new)

    func testGrowGestureFiresWithPointOriginWhenNoStrokeAtTap() {
        let v = SelectionView()
        var captured: GrowOrigin?
        v.onGrowGestureStarted = { captured = $0 }

        v.beginGrow(at: CGPoint(x: 50, y: 50), strokes: [])
        XCTAssertEqual(captured, .point(CGPoint(x: 50, y: 50)))
    }

    func testGrowGestureFiresWithStrokeOriginWhenTapHitsStroke() {
        let v = SelectionView()
        var captured: GrowOrigin?
        v.onGrowGestureStarted = { captured = $0 }

        let id = UUID()
        let s = Stroke(id: id, points: [
            StrokePoint(location: CGPoint(x: 50, y: 50), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        v.beginGrow(at: CGPoint(x: 51, y: 51), strokes: [s])
        // 51,51 is within the default hit-tolerance (8pt) of (50,50)
        XCTAssertEqual(captured, .stroke(strokeID: id, anchor: CGPoint(x: 51, y: 51)))
    }

    func testGrowEndFiresEndCallback() {
        let v = SelectionView()
        var ended = false
        v.onGrowGestureEnded = { ended = true }
        v.beginGrow(at: .zero, strokes: [])
        v.endGrow()
        XCTAssertTrue(ended)
    }
}
```

Run: expect FAIL.

- [ ] **Step 6.2: Delete old LassoOverlay file**

Delete `PenSculpt/Views/LassoOverlay.swift`.

- [ ] **Step 6.3: Write `SelectionOverlay.swift`**

Create `PenSculpt/Views/SelectionOverlay.swift`:

```swift
import SwiftUI
import UIKit

struct SelectionOverlay: UIViewRepresentable {
    @Binding var lassoPoints: [CGPoint]
    var allStrokes: [Stroke]
    var viewBridge: ViewBridge?
    var onLassoCompleted: ([CGPoint]) -> Void
    var onGrowGestureStarted: (GrowOrigin) -> Void
    var onGrowGestureEnded: () -> Void

    static let longPressMinimumDuration: CFTimeInterval = 0.15
    static let longPressAllowableMovement: CGFloat = 5.0
    static let strokeHitTolerance: CGFloat = 8.0

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SelectionView {
        let view = SelectionView()
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        view.onLassoCompleted = { context.coordinator.parent.onLassoCompleted($0) }
        view.onGrowGestureStarted = { context.coordinator.parent.onGrowGestureStarted($0) }
        view.onGrowGestureEnded = { context.coordinator.parent.onGrowGestureEnded() }
        view.installRecognizers()
        return view
    }

    func updateUIView(_ uiView: SelectionView, context: Context) {
        context.coordinator.parent = self
        uiView.targetView = viewBridge?.canvasView
        uiView.allStrokes = allStrokes
        if lassoPoints.isEmpty && !uiView.displayPoints.isEmpty {
            uiView.clearLasso()
        }
    }

    final class Coordinator {
        var parent: SelectionOverlay
        init(_ parent: SelectionOverlay) { self.parent = parent }
    }
}

final class SelectionView: UIView {
    var coordinator: SelectionOverlay.Coordinator?

    var displayPoints: [CGPoint] = []
    private(set) var hitTestPoints: [CGPoint] = []
    weak var targetView: UIView?
    private(set) var isClosed = false
    var allStrokes: [Stroke] = []

    var onLassoCompleted: (([CGPoint]) -> Void)?
    var onGrowGestureStarted: ((GrowOrigin) -> Void)?
    var onGrowGestureEnded: (() -> Void)?

    private var panRecognizer: UIPanGestureRecognizer?
    private var longPressRecognizer: UILongPressGestureRecognizer?

    // MARK: - Recognizer setup

    func installRecognizers() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        panRecognizer = pan

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lp.minimumPressDuration = SelectionOverlay.longPressMinimumDuration
        lp.allowableMovement = SelectionOverlay.longPressAllowableMovement
        addGestureRecognizer(lp)
        longPressRecognizer = lp

        // Pan must fail before long-press fires — i.e. if movement starts immediately,
        // we treat as lasso, not grow.
        lp.require(toFail: pan)
    }

    // MARK: - Lasso path (testable)

    func clearLasso() {
        displayPoints = []
        hitTestPoints = []
        isClosed = false
        coordinator?.parent.lassoPoints = []
        setNeedsDisplay()
    }

    func beginStroke(displayPoint: CGPoint, targetPoint: CGPoint) {
        if isClosed { clearLasso() }
        displayPoints = [displayPoint]
        hitTestPoints = [targetPoint]
        coordinator?.parent.lassoPoints = displayPoints
        setNeedsDisplay()
    }

    func continueStroke(displayPoint: CGPoint, targetPoint: CGPoint) {
        displayPoints.append(displayPoint)
        hitTestPoints.append(targetPoint)
        coordinator?.parent.lassoPoints = displayPoints
        setNeedsDisplay()
    }

    func endStroke() {
        if displayPoints.count > 2 {
            displayPoints.append(displayPoints[0])
            hitTestPoints.append(hitTestPoints[0])
            isClosed = true
            coordinator?.parent.lassoPoints = displayPoints
            onLassoCompleted?(hitTestPoints)
        } else {
            displayPoints = []
            hitTestPoints = []
            coordinator?.parent.lassoPoints = []
        }
        setNeedsDisplay()
    }

    // MARK: - Grow path (testable)

    func beginGrow(at canvasPoint: CGPoint, strokes: [Stroke]) {
        let origin: GrowOrigin
        if let hit = Self.hitStroke(at: canvasPoint, in: strokes,
                                    tolerance: SelectionOverlay.strokeHitTolerance) {
            origin = .stroke(strokeID: hit.id, anchor: canvasPoint)
        } else {
            origin = .point(canvasPoint)
        }
        onGrowGestureStarted?(origin)
    }

    func endGrow() {
        onGrowGestureEnded?()
    }

    static func hitStroke(at point: CGPoint, in strokes: [Stroke], tolerance: CGFloat) -> Stroke? {
        var best: (Stroke, CGFloat)?
        for s in strokes {
            for sp in s.points {
                let d = hypot(sp.location.x - point.x, sp.location.y - point.y)
                if d <= tolerance {
                    if let cur = best, cur.1 <= d { continue }
                    best = (s, d)
                }
            }
        }
        return best?.0
    }

    // MARK: - Recognizer handlers

    private func points(for location: CGPoint, in view: UIView) -> (display: CGPoint, target: CGPoint) {
        let display = location
        let target = targetView.map { view.convert(location, to: $0) } ?? display
        return (display, target)
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        let location = gr.location(in: self)
        let p = points(for: location, in: self)
        switch gr.state {
        case .began:
            beginStroke(displayPoint: p.display, targetPoint: p.target)
        case .changed:
            continueStroke(displayPoint: p.display, targetPoint: p.target)
        case .ended, .cancelled:
            endStroke()
        default:
            break
        }
    }

    @objc private func handleLongPress(_ gr: UILongPressGestureRecognizer) {
        switch gr.state {
        case .began:
            let display = gr.location(in: self)
            let target = targetView.map { gr.view!.convert(display, to: $0) } ?? display
            beginGrow(at: target, strokes: allStrokes)
        case .ended, .cancelled, .failed:
            endGrow()
        default:
            break
        }
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard displayPoints.count > 1, let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [8, 4])
        ctx.beginPath()
        ctx.move(to: displayPoints[0])
        for p in displayPoints.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }
}
```

- [ ] **Step 6.4: Update `SelectionCoordinateTests.swift` to use renamed types**

Replace every `LassoView` with `SelectionView` and every `LassoSelection` with `LassoStrategy` in `PenSculptTests/SelectionCoordinateTests.swift`.

- [ ] **Step 6.5: Delete old test file**

Delete `PenSculptTests/LassoViewTests.swift`. Its cases live in `SelectionOverlayTests.swift` now.

- [ ] **Step 6.6: Run all tests, expect green**

Run: `xcodebuild test -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -30`. Expected: PASS.

If `testLassoBeginAndEndProducesPolygon` fails because the closure was nil — make sure `installRecognizers()` does not overwrite the test-injected closures. The structure above sets closures in `makeUIView`, but the unit tests construct `SelectionView` directly and assign them. Both paths must work.

- [ ] **Step 6.7: Commit**

```bash
git add -A
git commit -m "feat(grow-selection): rename LassoOverlay→SelectionOverlay, add long-press recognizer"
```

---

## Phase 5 — Integration

### Task 7: Update `DrawingViewModel` — own grow session and drive ticks via `CADisplayLink`

**Files:**
- Modify: `PenSculpt/Views/DrawingViewModel.swift`
- Modify: `PenSculptTests/DrawingViewModelTests.swift`

The view model gains:
- `growSession: GrowSession?` — non-nil while user is holding.
- `growthFrame: GrowFrame?` — published, drives `GrowthVisualization`.
- `displayLink: CADisplayLink?` — drives ticks. Created on grow start, invalidated on end.
- Methods: `handleGrowGestureStarted(origin:)`, `handleGrowGestureEnded()`.
- `selectedStrokeIDs` is written from `finalize()` on end.

Because `DrawingViewModel` is `@Observable`, every mutation triggers a SwiftUI update.

- [ ] **Step 7.1: Write failing tests**

Add to `PenSculptTests/DrawingViewModelTests.swift`:

```swift
func testGrowGestureStartCreatesSession() {
    let vm = DrawingViewModel()
    let id = UUID()
    let s = Stroke(id: id, points: [
        StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
    ])
    vm.canvas.strokes = [s]
    vm.handleGrowGestureStarted(origin: .stroke(strokeID: id, anchor: .zero))
    XCTAssertNotNil(vm.growSession)
    XCTAssertNotNil(vm.growthFrame)
}

func testGrowGestureEndCommitsSelection() {
    let vm = DrawingViewModel()
    let id = UUID()
    let s = Stroke(id: id, points: [
        StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
    ])
    vm.canvas.strokes = [s]
    vm.handleGrowGestureStarted(origin: .stroke(strokeID: id, anchor: .zero))
    vm.handleGrowGestureEnded()
    XCTAssertNil(vm.growSession)
    XCTAssertNil(vm.growthFrame)
    XCTAssertEqual(vm.selectedStrokeIDs, [id])
}
```

Run: expect FAIL — methods undefined.

- [ ] **Step 7.2: Implement view-model changes**

In `PenSculpt/Views/DrawingViewModel.swift`:

Add imports if missing: `import QuartzCore`.

Add stored properties (near `selectedStrokeIDs`):

```swift
var growSession: GrowSession?
var growthFrame: GrowFrame?
private var displayLink: CADisplayLink?
private var lastTickTimestamp: CFTimeInterval = 0
```

Add methods (alongside `handleLassoCompleted`):

```swift
func handleGrowGestureStarted(origin: GrowOrigin) {
    cancelLasso()
    let session = GrowStrategy.start(origin: origin, canvas: canvas)
    growSession = session
    growthFrame = GrowFrame(
        radius: session.currentRadius,
        center: origin.anchor,
        includedStrokeIDs: session.includedStrokeIDs,
        nextCandidateID: session.nextCandidateID,
        isPaused: session.isPaused
    )
    startDisplayLink()
}

func handleGrowGestureEnded() {
    stopDisplayLink()
    if let session = growSession {
        selectedStrokeIDs = session.finalize()
    }
    growSession = nil
    growthFrame = nil
}

private func startDisplayLink() {
    stopDisplayLink()
    let link = CADisplayLink(target: DisplayLinkProxy(viewModel: self),
                             selector: #selector(DisplayLinkProxy.tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    lastTickTimestamp = CACurrentMediaTime()
}

private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
}

fileprivate func displayLinkTick(_ link: CADisplayLink) {
    let now = link.timestamp
    let dt = max(0, now - lastTickTimestamp)
    lastTickTimestamp = now
    guard let session = growSession else { return }
    let frame = session.tick(deltaTime: dt)
    growthFrame = frame
}

private func cancelLasso() {
    lassoPoints = []
}
```

Add the proxy at file scope (CADisplayLink retains its target; use weak-ref proxy to avoid retain cycle):

```swift
private final class DisplayLinkProxy {
    weak var viewModel: DrawingViewModel?
    init(viewModel: DrawingViewModel) { self.viewModel = viewModel }
    @objc func tick(_ link: CADisplayLink) { viewModel?.displayLinkTick(link) }
}
```

- [ ] **Step 7.3: Run tests, expect green**

Run: `xcodebuild test ... -only-testing:PenSculptTests/DrawingViewModelTests`. Expected: new tests PASS.

Note: `CADisplayLink` does not tick in unit tests by default; the new tests don't depend on a tick — they only verify state transitions. The first `growthFrame` is published synchronously inside `handleGrowGestureStarted`, so the assertion holds.

- [ ] **Step 7.4: Commit**

```bash
git add PenSculpt/Views/DrawingViewModel.swift PenSculptTests/DrawingViewModelTests.swift
git commit -m "feat(grow-selection): wire GrowSession lifecycle and display-link tick into DrawingViewModel"
```

---

### Task 8: Wire up `DrawingScreen` to use `SelectionOverlay` + `GrowthVisualization`

**Files:**
- Modify: `PenSculpt/Views/DrawingScreen.swift`

Replace the `LassoOverlay` block in `selectModeOverlay` and add a `growthVisualizationLayer`.

- [ ] **Step 8.1: Update `selectModeOverlay`**

In `PenSculpt/Views/DrawingScreen.swift`, replace the `LassoOverlay(...)` block (around line 87) with:

```swift
SelectionOverlay(
    lassoPoints: $vm.lassoPoints,
    allStrokes: vm.canvas.strokes,
    viewBridge: viewBridge,
    onLassoCompleted: { vm.handleLassoCompleted(polygon: $0) },
    onGrowGestureStarted: { vm.handleGrowGestureStarted(origin: $0) },
    onGrowGestureEnded: { vm.handleGrowGestureEnded() }
)
.ignoresSafeArea()
```

- [ ] **Step 8.2: Add growth visualization layer**

Add this computed property near `selectionHighlightLayer`:

```swift
@ViewBuilder
private var growthVisualizationLayer: some View {
    if let frame = vm.growthFrame {
        GrowthVisualization(frame: frame, allStrokes: vm.canvas.strokes, viewBridge: viewBridge)
            .ignoresSafeArea()
    }
}
```

In the body where `selectionHighlightLayer` is rendered, add `growthVisualizationLayer` immediately after it (so the visualization sits above the highlight, both above the canvas, both below the lasso overlay).

- [ ] **Step 8.3: Build to verify**

Run: `xcodebuild build -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -10`. Expected: BUILD SUCCEEDED.

- [ ] **Step 8.4: Commit**

```bash
git add PenSculpt/Views/DrawingScreen.swift
git commit -m "feat(grow-selection): wire SelectionOverlay and GrowthVisualization into DrawingScreen"
```

---

### Task 9: Update `TooltipID.modeToggle` text

**Files:**
- Modify: `PenSculpt/Views/Tooltips/TooltipID.swift`

- [ ] **Step 9.1: Update the tooltip content**

In `PenSculpt/Views/Tooltips/TooltipID.swift`, change the line:

```swift
case .modeToggle:         return .init(title: "Selection mode", subtitle: "Switch between drawing and lasso selection")
```

to:

```swift
case .modeToggle:         return .init(title: "Selection mode", subtitle: "Drag to lasso · Hold on a stroke or canvas to grow selection")
```

- [ ] **Step 9.2: Run TooltipIDTests, expect green**

Run: `xcodebuild test ... -only-testing:PenSculptTests/TooltipIDTests`. Expected: PASS (existing test only checks non-empty title).

- [ ] **Step 9.3: Commit**

```bash
git add PenSculpt/Views/Tooltips/TooltipID.swift
git commit -m "feat(grow-selection): update modeToggle tooltip to mention grow selection"
```

---

## Phase 6 — Verification

### Task 10: Manual verification on iPad

**Prerequisites:** iPad with Apple Pencil paired and recognized. App built and deployed via Xcode.

- [ ] **Step 10.1: Lasso regression**

Enter Select mode. Drag the Pencil in a closed shape. Confirm:
- Dashed blue path follows the Pencil.
- On release, strokes inside the polygon get the blue selection highlight.
- Sculpt button appears (existing flow).
- Undo reverses the selection.

- [ ] **Step 10.2: Grow from canvas point**

Enter Select mode. Tap+hold (no movement) on **empty canvas** near a few strokes. Confirm:
- After ~150ms a translucent blue circle appears at the Pencil tip and grows.
- As the circle reaches strokes, they light up in blue.
- Next stroke about to enter pulses faintly.
- When the algorithm hits a gap, a yellow halo appears around the circle.

- [ ] **Step 10.3: Grow from stroke**

Tap+hold **on top of an existing stroke**. Confirm:
- That stroke is highlighted immediately at t=0.
- Circle grows around the tap point and admits neighbors normally.

- [ ] **Step 10.4: Casa+janela scenario**

Draw a simple house: a square outline plus a smaller square inside (the "window") with a small visible gap (~3-5pt) between window and wall. Tap+hold on the window. Confirm:
- Window fills in first.
- Yellow halo appears as the algorithm approaches the wall.
- Releasing during the halo selects only the window.
- Holding through the halo eventually adds the wall.

- [ ] **Step 10.5: Gesture exclusivity**

In Select mode:
- Drag immediately → lasso only, no grow visualization.
- Hold still → grow only, no lasso path.
- Tap and small jitter (<5pt) → grow fires.
- Tap and movement >5pt within 150ms → lasso fires.

- [ ] **Step 10.6: Cancellation via Undo**

Run grow selection, release. Run Undo. Confirm selection clears.

- [ ] **Step 10.7: Tooltip discoverability**

Hover Pencil over the mode-toggle button (or long-press if hover unavailable). Confirm tooltip reads "Selection mode — Drag to lasso · Hold on a stroke or canvas to grow selection".

- [ ] **Step 10.8: Backgrounding during hold**

Start grow gesture, send app to background mid-hold. Reopen. Confirm:
- No partial selection committed.
- App is in a clean state (no stuck circle on screen).

- [ ] **Step 10.9: Tune constants if needed**

If any of these feel off, adjust the relevant tunable in `GrowStrategy.swift` or `GrowthVisualization.swift` and re-test:
- Growth too fast/slow → `baseGrowthSpeed`.
- Pause too aggressive/lazy → `densityPauseThreshold`.
- Pulse too jarring/subtle → `pulsePeriod`, `candidateColor` opacity.

Commit any tuning changes:

```bash
git add PenSculpt/Drawing/Selection/GrowStrategy.swift PenSculpt/Views/GrowthVisualization.swift
git commit -m "tune(grow-selection): adjust constants after manual verification"
```

- [ ] **Step 10.10: Run the full test suite a final time**

Run: `xcodebuild test -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -30`. Expected: all tests pass.

---

## Out of scope (do not do in this plan)

- Plan B UI (Lasso↔Grow toggle inside Select mode). Only revisit if user reports discoverability problems.
- Optimizing `DensityProbe` / `GrowSession` with a spatial index. Naive O(F×C×P) is fine for first version.
- Any change to sculpt selection — grow is 2D-only.
- Persisting grow-related state in `PenSculptDocument`. The session is ephemeral; only `selectedStrokeIDs` survives, and that already roundtrips today.
