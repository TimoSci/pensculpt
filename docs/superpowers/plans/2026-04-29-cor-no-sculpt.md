# Cor no Sculpt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow surface strokes drawn in `SculptScreen` to use the user-selected color from `Canvas.activeColor` instead of the hardcoded blue, with full propagation through model, renderer, projection, and UI.

**Architecture:** Per-stroke `color: CodableColor` on `SurfaceStroke` (decoded with blue fallback for backwards compat). Color flows: `Canvas.activeColor` (`DrawingScreen`) → `SculptScreen` (new params + swatch button) → `MetalCanvasView` (new param) → `Coordinator.activeColor` + `SculptRenderer.currentStrokeColor` → embedded in newly created `SurfaceStroke`. Renderer reads `stroke.color` instead of hardcoded constant. `projectTo2D()` and `reprojected()` propagate color.

**Tech Stack:** Swift 5.10+, SwiftUI, Metal/MetalKit, XCTest. iOS 17.5+ target. Tests run via `xcodebuild` against iPad Pro simulator.

**Spec:** `docs/superpowers/specs/2026-04-29-cor-no-sculpt-design.md`

---

## File Structure

**Modify:**
- `PenSculpt/Models/SculptObject.swift` — add `color` to `SurfaceStroke`, propagate in `projectTo2D()` and `reprojected(onto:)`
- `PenSculpt/Models/Stroke.swift` — add `CodableColor.simd4(opacity:)` helper
- `PenSculpt/Rendering/SculptRenderer.swift` — add `currentStrokeColor`, use `stroke.color` in `drawSurfaceStrokes`
- `PenSculpt/Rendering/MetalCanvasView.swift` — receive `activeColor`, propagate to renderer + Coordinator, set on new `SurfaceStroke`
- `PenSculpt/Views/SculptScreen.swift` — receive color params, pass to `MetalCanvasView`, add swatch button in bottom toolbar
- `PenSculpt/Views/DrawingScreen.swift` — pass color params + callbacks to `SculptScreen`
- `TODO.md` — mark color-no-sculpt complete

**Create:**
- `PenSculptTests/SurfaceStrokeColorTests.swift` — Codable roundtrip, legacy decode fallback, `projectTo2D()` color propagation, `reprojected()` color preservation, `simd4()` helper

**No new shaders or pipeline changes** — the existing fragment shader already accepts per-vertex color via the `colors[]` buffer.

---

## Task 1: Add `color` field to `SurfaceStroke` (model + Codable)

**Files:**
- Modify: `PenSculpt/Models/SculptObject.swift:4-25`
- Create: `PenSculptTests/SurfaceStrokeColorTests.swift`

- [ ] **Step 1: Write the failing test for Codable roundtrip preserving color**

Create `PenSculptTests/SurfaceStrokeColorTests.swift` with:

```swift
import XCTest
import simd
@testable import PenSculpt

final class SurfaceStrokeColorTests: XCTestCase {

    func testCodableRoundTripPreservesColor() throws {
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let stroke = SurfaceStroke(
            points: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 1)],
            widths: [3, 3],
            opacity: 0.8,
            color: red
        )
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(SurfaceStroke.self, from: data)
        XCTAssertEqual(decoded.color, red)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests/testCodableRoundTripPreservesColor 2>&1 | tail -20`

Expected: build error (`extra argument 'color'` or similar) or test fail because `color` doesn't exist yet.

- [ ] **Step 3: Modify `SurfaceStroke` to add `color` field**

Edit `PenSculpt/Models/SculptObject.swift`, replacing the struct definition (lines 4-25):

```swift
struct SurfaceStroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var points: [SIMD3<Float>]
    var widths: [Float]
    var opacity: Float
    var color: CodableColor

    init(id: UUID = UUID(), points: [SIMD3<Float>] = [], widths: [Float] = [],
         opacity: Float = 1, color: CodableColor = .black) {
        self.id = id
        self.points = points
        self.widths = widths
        self.opacity = opacity
        self.color = color
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decode([SIMD3<Float>].self, forKey: .points)
        widths = try container.decodeIfPresent([Float].self, forKey: .widths)
            ?? Array(repeating: 3.0, count: points.count)
        opacity = try container.decodeIfPresent(Float.self, forKey: .opacity) ?? 1
        color = try container.decodeIfPresent(CodableColor.self, forKey: .color)
            ?? CodableColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests/testCodableRoundTripPreservesColor 2>&1 | tail -10`

Expected: PASS.

- [ ] **Step 5: Add legacy decode test (no color field → blue fallback)**

Append to `PenSculptTests/SurfaceStrokeColorTests.swift`:

```swift
    func testLegacyDecodeFallsBackToHistoricBlue() throws {
        // JSON without `color` field — represents docs saved before this feature.
        let legacyJSON = """
        {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "points": [{"x": 0, "y": 0, "z": 0}, {"x": 1, "y": 1, "z": 1}],
            "widths": [3, 3],
            "opacity": 1
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SurfaceStroke.self, from: legacyJSON)
        XCTAssertEqual(decoded.color.red, 0.2, accuracy: 0.001)
        XCTAssertEqual(decoded.color.green, 0.2, accuracy: 0.001)
        XCTAssertEqual(decoded.color.blue, 0.8, accuracy: 0.001)
        XCTAssertEqual(decoded.color.alpha, 1.0, accuracy: 0.001)
    }
```

- [ ] **Step 6: Run the legacy decode test**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests/testLegacyDecodeFallsBackToHistoricBlue 2>&1 | tail -10`

Expected: PASS.

- [ ] **Step 7: Run the full SurfaceStrokeColorTests suite to confirm both pass**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests 2>&1 | tail -10`

Expected: both tests PASS.

- [ ] **Step 8: Commit**

```bash
git add PenSculpt/Models/SculptObject.swift PenSculptTests/SurfaceStrokeColorTests.swift
git commit -m "feat(sculpt): add color field to SurfaceStroke with legacy fallback"
```

---

## Task 2: Add `CodableColor.simd4(opacity:)` helper

**Files:**
- Modify: `PenSculpt/Models/Stroke.swift` (append to file)
- Modify: `PenSculptTests/SurfaceStrokeColorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PenSculptTests/SurfaceStrokeColorTests.swift`:

```swift
    func testSimd4HelperConvertsAndAppliesOpacity() {
        let color = CodableColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8)
        let v = color.simd4(opacity: 0.5)
        XCTAssertEqual(v.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(v.y, 0.5, accuracy: 0.001)
        XCTAssertEqual(v.z, 0.75, accuracy: 0.001)
        XCTAssertEqual(v.w, 0.4, accuracy: 0.001)  // 0.8 * 0.5
    }

    func testSimd4HelperDefaultOpacityIsIdentity() {
        let color = CodableColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let v = color.simd4()
        XCTAssertEqual(v.w, 1.0, accuracy: 0.001)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests/testSimd4HelperConvertsAndAppliesOpacity 2>&1 | tail -10`

Expected: build error or fail (`simd4` not defined).

- [ ] **Step 3: Add the helper to `Stroke.swift`**

Edit `PenSculpt/Models/Stroke.swift`. After the existing `extension CodableColor` block (line 57-62 inside `#if canImport(UIKit)`), add a separate extension above the `#if`:

Replace lines 53-62 (the entire `#if canImport(UIKit)` block) with:

```swift
import simd

extension CodableColor {
    func simd4(opacity: Float = 1) -> SIMD4<Float> {
        SIMD4(Float(red), Float(green), Float(blue), Float(alpha) * opacity)
    }
}

#if canImport(UIKit)
import UIKit

extension CodableColor {
    func uiColor(opacityMultiplier: CGFloat = 1) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha * opacityMultiplier)
    }
}
#endif
```

- [ ] **Step 4: Run both new tests**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests 2>&1 | tail -10`

Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Models/Stroke.swift PenSculptTests/SurfaceStrokeColorTests.swift
git commit -m "feat(stroke): add CodableColor.simd4(opacity:) helper"
```

---

## Task 3: `projectTo2D()` propagates stroke color

**Files:**
- Modify: `PenSculpt/Models/SculptObject.swift:30-42`
- Modify: `PenSculptTests/SurfaceStrokeColorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PenSculptTests/SurfaceStrokeColorTests.swift`:

```swift
    func testProjectTo2DUsesStrokeColor() {
        let green = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
        let stroke = SurfaceStroke(
            points: [SIMD3<Float>(10, 20, 0), SIMD3<Float>(30, 40, 0)],
            widths: [3, 3],
            opacity: 1,
            color: green
        )
        let projected = stroke.projectTo2D()
        XCTAssertEqual(projected.color.red, 0, accuracy: 0.001)
        XCTAssertEqual(projected.color.green, 1, accuracy: 0.001)
        XCTAssertEqual(projected.color.blue, 0, accuracy: 0.001)
    }

    func testProjectTo2DAppliesOpacityToAlpha() {
        let translucentRed = CodableColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        let stroke = SurfaceStroke(
            points: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 1, 0)],
            widths: [3, 3],
            opacity: 0.5,
            color: translucentRed
        )
        let projected = stroke.projectTo2D()
        XCTAssertEqual(projected.color.alpha, 0.25, accuracy: 0.001)  // 0.5 * 0.5
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests/testProjectTo2DUsesStrokeColor 2>&1 | tail -10`

Expected: FAIL — current implementation hardcodes blue.

- [ ] **Step 3: Update `projectTo2D()`**

In `PenSculpt/Models/SculptObject.swift`, replace the body of `projectTo2D()` (lines 30-42):

```swift
    func projectTo2D() -> Stroke {
        let strokePoints = points.enumerated().map { i, p in
            StrokePoint(
                location: CGPoint(x: CGFloat(p.x), y: CGFloat(-p.y)),
                pressure: CGFloat(i < widths.count ? widths[i] / 8 : 0.5),
                tilt: .pi / 2,
                azimuth: 0,
                timestamp: TimeInterval(i) * 0.01
            )
        }
        let projColor = CodableColor(
            red: color.red,
            green: color.green,
            blue: color.blue,
            alpha: color.alpha * CGFloat(opacity)
        )
        return Stroke(points: strokePoints, color: projColor)
    }
```

- [ ] **Step 4: Run both new tests**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests 2>&1 | tail -10`

Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Models/SculptObject.swift PenSculptTests/SurfaceStrokeColorTests.swift
git commit -m "feat(sculpt): projectTo2D propagates stroke color"
```

---

## Task 4: `reprojected(onto:)` preserves color

**Files:**
- Modify: `PenSculpt/Models/SculptObject.swift:46-64`
- Modify: `PenSculptTests/SurfaceStrokeColorTests.swift`

- [ ] **Step 1: Write the failing test**

Append to `PenSculptTests/SurfaceStrokeColorTests.swift`:

```swift
    func testReprojectedPreservesColorAndOpacity() {
        // Build a tiny mesh (a single triangle on the z=0 plane large enough to catch all points).
        let v0 = MeshVertex(position: SIMD3<Float>(-100, -100, 0), normal: SIMD3<Float>(0, 0, 1))
        let v1 = MeshVertex(position: SIMD3<Float>( 100, -100, 0), normal: SIMD3<Float>(0, 0, 1))
        let v2 = MeshVertex(position: SIMD3<Float>(   0,  100, 0), normal: SIMD3<Float>(0, 0, 1))
        let face = MeshFace(indices: SIMD3<UInt32>(0, 1, 2))
        let mesh = Mesh(vertices: [v0, v1, v2], faces: [face])

        let purple = CodableColor(red: 0.5, green: 0, blue: 0.5, alpha: 1)
        let stroke = SurfaceStroke(
            points: [SIMD3<Float>(0, 0, 5), SIMD3<Float>(10, 0, 5)],  // above the plane, z > 0
            widths: [3, 3],
            opacity: 0.7,
            color: purple
        )

        let reprojected = stroke.reprojected(
            onto: mesh,
            rayDir: SIMD3<Float>(0, 0, -1),  // cast straight down onto the plane
            offset: 0
        )
        XCTAssertNotNil(reprojected)
        XCTAssertEqual(reprojected?.color, purple)
        XCTAssertEqual(reprojected?.opacity, 0.7, accuracy: 0.001)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests/testReprojectedPreservesColorAndOpacity 2>&1 | tail -10`

Expected: FAIL — current implementation drops `color` and `opacity` (uses defaults from new `init`, which means `color = .black`, `opacity = 1`).

- [ ] **Step 3: Update `reprojected(onto:)`**

In `PenSculpt/Models/SculptObject.swift`, replace the return line of `reprojected(onto:)` (line 63):

```swift
        return SurfaceStroke(id: id, points: newPoints, widths: newWidths,
                             opacity: opacity, color: color)
```

(replace the existing `return SurfaceStroke(id: id, points: newPoints, widths: newWidths)`)

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/SurfaceStrokeColorTests 2>&1 | tail -10`

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Models/SculptObject.swift PenSculptTests/SurfaceStrokeColorTests.swift
git commit -m "feat(sculpt): reprojected preserves stroke color and opacity"
```

---

## Task 5: Renderer uses `stroke.color` and exposes `currentStrokeColor`

**Files:**
- Modify: `PenSculpt/Rendering/SculptRenderer.swift`

This task has no unit test (rendering is GPU-side; covered by manual verification at end of plan).

- [ ] **Step 1: Add `currentStrokeColor` field to `SculptRenderer`**

In `PenSculpt/Rendering/SculptRenderer.swift`, find line 56 (`var surfaceSpaceStrokes: Bool = false`) and add the new field below it:

```swift
    var surfaceSpaceStrokes: Bool = false
    var currentStrokeColor: CodableColor = .black
```

- [ ] **Step 2: Replace hardcoded blue for saved strokes**

In `PenSculpt/Rendering/SculptRenderer.swift`, find line 296 inside `drawSurfaceStrokes`:

```swift
                let color = SIMD4<Float>(0.2, 0.2, 0.8, stroke.opacity)
```

Replace with:

```swift
                let color = stroke.color.simd4(opacity: stroke.opacity)
```

- [ ] **Step 3: Replace hardcoded blue for in-progress preview**

In the same function, find lines 305-306:

```swift
            drawStrokeStrip(currentStrokePoints, widths: widths,
                            color: SIMD4<Float>(0.2, 0.2, 0.8, brushOpacity * 0.6), encoder: encoder)
```

Replace with:

```swift
            drawStrokeStrip(currentStrokePoints, widths: widths,
                            color: currentStrokeColor.simd4(opacity: brushOpacity * 0.6), encoder: encoder)
```

- [ ] **Step 4: Build to verify compiles**

Run: `xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build 2>&1 | tail -15`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run all existing tests to confirm no regression**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -20`

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add PenSculpt/Rendering/SculptRenderer.swift
git commit -m "feat(renderer): use stroke.color and currentStrokeColor instead of hardcoded blue"
```

---

## Task 6: `MetalCanvasView` wires `activeColor`

**Files:**
- Modify: `PenSculpt/Rendering/MetalCanvasView.swift`

- [ ] **Step 1: Add `activeColor` parameter to `MetalCanvasView`**

In `PenSculpt/Rendering/MetalCanvasView.swift`, find the struct property list (lines 57-73) and add a new property after `brushOpacity` (line 67):

```swift
    var brushOpacity: Float = 1
    var activeColor: CodableColor = .black
```

- [ ] **Step 2: Add `activeColor` to the `Coordinator`**

In the same file, find the `Coordinator` class declaration (line 159). After `var renderer: SculptRenderer?` (line 160), add:

```swift
        var activeColor: CodableColor = .black
```

- [ ] **Step 3: Propagate `activeColor` in `updateUIView`**

In `updateUIView` (lines 135-153), after the line `context.coordinator.renderer?.brushOpacity = brushOpacity` (line 148), add:

```swift
        context.coordinator.renderer?.currentStrokeColor = activeColor
        context.coordinator.activeColor = activeColor
```

- [ ] **Step 4: Pass color when constructing the new `SurfaceStroke`**

Find the existing stroke construction at lines 315-317:

```swift
                    let stroke = SurfaceStroke(points: renderer.currentStrokePoints,
                                                widths: renderer.currentStrokeWidths,
                                                opacity: renderer.brushOpacity)
```

Replace with:

```swift
                    let stroke = SurfaceStroke(points: renderer.currentStrokePoints,
                                                widths: renderer.currentStrokeWidths,
                                                opacity: renderer.brushOpacity,
                                                color: activeColor)
```

- [ ] **Step 5: Build to verify compiles**

Run: `xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build 2>&1 | tail -15`

Expected: build succeeds. (Existing `MetalCanvasView` callers will compile because `activeColor` has a default value.)

- [ ] **Step 6: Run all tests to confirm no regression**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -20`

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add PenSculpt/Rendering/MetalCanvasView.swift
git commit -m "feat(metal-canvas-view): receive activeColor and embed in new SurfaceStrokes"
```

---

## Task 7: `SculptScreen` receives color params, passes to canvas, adds swatch

**Files:**
- Modify: `PenSculpt/Views/SculptScreen.swift`

- [ ] **Step 1: Add color params to `SculptScreen`**

In `PenSculpt/Views/SculptScreen.swift`, find the struct property block (lines 4-29). After `var config: SculptConfig = .default` (line 8), add:

```swift
    var activeColor: CodableColor
    var recentColors: [CodableColor]
    var onSelectPresetColor: (CodableColor) -> Void
    var onSelectCustomColor: (CodableColor) -> Void
```

After `@State private var showScopeDialog = false` (line 28), add:

```swift
    @State private var showColorPopover = false
```

- [ ] **Step 2: Pass `activeColor` into `MetalCanvasView`**

In the `MetalCanvasView(...)` initializer (lines 32-49), add `activeColor` between `brushOpacity` and `onObjectTapped`. The block becomes:

```swift
        MetalCanvasView(
            sculptObjects: sculptObjects,
            activeObjectID: activeObjectID,
            config: config,
            isRotateMode: isRotateMode,
            isDeformMode: isDeformMode,
            isSmoothMode: isSmoothMode,
            isEraseStrokeMode: isEraseStrokeMode,
            surfaceSpaceStrokes: surfaceSpaceStrokes,
            brushSize: Float(brushSize),
            brushOpacity: Float(brushOpacity),
            activeColor: activeColor,
            onObjectTapped: cycleActiveObject,
            onSurfaceStrokeCompleted: handleSurfaceStroke,
            onMeshDeformed: handleMeshDeformed,
            onDeformCursor: { deformCursor = $0 },
            onRendererReady: { replace, morph, cacheBVH in Task { @MainActor in rendererReplaceMesh = replace; rendererMorphMesh = morph; rendererCacheBVH = cacheBVH } },
            onViewReady: { view in Task { @MainActor in metalView = view } }
        )
```

- [ ] **Step 3: Add the swatch button to the bottom toolbar**

Find the bottom overlay (lines 129-148):

```swift
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                BrushControls(brushSize: $brushSize, brushOpacity: $brushOpacity, isDeformMode: isDeformMode)

                Divider().frame(height: 24)

                Button {
                    surfaceSpaceStrokes.toggle()
                } label: {
                    Image(systemName: surfaceSpaceStrokes ? "cube.fill" : "square.fill")
                        .font(.caption)
                        .foregroundStyle(surfaceSpaceStrokes ? .blue : .secondary)
                }
                .help(surfaceSpaceStrokes ? "Surface-space strokes" : "Screen-space strokes")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.bottom, 20)
        }
```

Replace the `HStack` body (the inner content between `HStack(spacing: 12) {` and the matching `}`) so the swatch comes first:

```swift
            HStack(spacing: 12) {
                Button { showColorPopover = true } label: {
                    Circle()
                        .fill(Color(activeColor))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
                }
                .popover(isPresented: $showColorPopover) {
                    ColorPickerPopover(
                        activeColor: activeColor,
                        recentColors: recentColors,
                        onSelectPreset: onSelectPresetColor,
                        onSelectCustom: onSelectCustomColor
                    )
                }

                Divider().frame(height: 24)

                BrushControls(brushSize: $brushSize, brushOpacity: $brushOpacity, isDeformMode: isDeformMode)

                Divider().frame(height: 24)

                Button {
                    surfaceSpaceStrokes.toggle()
                } label: {
                    Image(systemName: surfaceSpaceStrokes ? "cube.fill" : "square.fill")
                        .font(.caption)
                        .foregroundStyle(surfaceSpaceStrokes ? .blue : .secondary)
                }
                .help(surfaceSpaceStrokes ? "Surface-space strokes" : "Screen-space strokes")
            }
```

- [ ] **Step 4: Build to verify compiles (will fail until Task 8 wires DrawingScreen)**

Run: `xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build 2>&1 | tail -15`

Expected: build error in `DrawingScreen` because `SculptScreen` initializer now requires the new params. This is OK — Task 8 fixes it. Confirm the error is exactly that (missing `activeColor:`/`recentColors:`/`onSelectPresetColor:`/`onSelectCustomColor:` arguments) and nothing else.

- [ ] **Step 5: Commit (build still red)**

```bash
git add PenSculpt/Views/SculptScreen.swift
git commit -m "feat(sculpt-screen): add color params, swatch button, pass color to canvas"
```

---

## Task 8: `DrawingScreen` passes color params + callbacks to `SculptScreen`

**Files:**
- Modify: `PenSculpt/Views/DrawingScreen.swift:34`

- [ ] **Step 1: Locate the existing `SculptScreen` instantiation**

Run: `grep -n "SculptScreen(" /Users/alexandre/documents_copy/code/pensculpt/PenSculpt/Views/DrawingScreen.swift`

Expected: shows the call site on or near line 34 inside `.fullScreenCover`.

- [ ] **Step 2: Read the existing call site to capture the current arguments**

Run: `sed -n '30,50p' /Users/alexandre/documents_copy/code/pensculpt/PenSculpt/Views/DrawingScreen.swift`

This shows you the current `SculptScreen(...)` call so you preserve all existing arguments when adding the new ones.

- [ ] **Step 3: Add the four new arguments to the `SculptScreen(...)` call**

Inside the `.fullScreenCover { SculptScreen(...) }` block, append after the last existing argument (preserving any trailing closure / existing args). The new arguments to add are:

```swift
                activeColor: vm.canvas.activeColor,
                recentColors: vm.canvas.recentColors,
                onSelectPresetColor: { setActiveColorWithUndo($0, addToRecents: false) },
                onSelectCustomColor: { setActiveColorWithUndo($0, addToRecents: true) }
```

(Insert into the `SculptScreen(...)` argument list. Do not duplicate existing arguments. Keep existing argument order.)

- [ ] **Step 4: Build the project**

Run: `xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build 2>&1 | tail -15`

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run the full test suite**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' 2>&1 | tail -25`

Expected: all tests PASS, including the new `SurfaceStrokeColorTests`.

- [ ] **Step 6: Commit**

```bash
git add PenSculpt/Views/DrawingScreen.swift
git commit -m "feat(drawing-screen): pass activeColor and color callbacks to SculptScreen"
```

---

## Task 9: Manual verification + TODO update

**Files:**
- Modify: `TODO.md`

- [ ] **Step 1: Manual smoke test on simulator**

Build and run the app. Walk through each scenario, noting any failure:

1. **Color applies to new sculpt strokes:** Create a drawing → enter Sculpt → select red in the swatch → draw a surface stroke → confirm it renders red (not blue).
2. **Color is shared with 2D:** Change color in Sculpt swatch → exit to DrawingScreen → confirm the 2D toolbar swatch shows the same color, and new 2D strokes use it.
3. **Recent colors sync:** Pick a custom color in Sculpt → exit → confirm it appears in the 2D `recentColors` list.
4. **Re-infer preserves color:** Draw colored surface strokes → tap re-infer (`arrow.clockwise.circle.fill`) → confirm strokes keep their colors after the new mesh appears.
5. **Re-infer morph preserves color:** Same with the `sparkles` (morph) button.
6. **Mesh deformation preserves color:** Enter deform mode, push the mesh — surface strokes should keep their colors as they move with the mesh.
7. **Persistence:** Quit and relaunch the app, reopen the document, confirm colored strokes survive a save/load cycle.
8. **Project to 2D uses color:** Toggle auto-project (`arrow.down.doc`) ON → exit Sculpt → confirm projected 2D strokes appear in the original 3D color (not blue, not black).
9. **Legacy doc compat:** Open a `.pensculpt` doc saved before this feature (if you have one). Existing surface strokes should still render in the historic blue.

If any scenario fails, fix the underlying issue (likely a missed wiring) before proceeding. Each fix should be its own commit.

- [ ] **Step 2: Update `TODO.md`**

In `TODO.md`, find the Stage 2 → Inference Pipeline section. There is no specific "color in sculpt" line today, but the spec describes future work. Append a checked entry under `## Future Stages` after `Color picker and color strokes`:

Find the line:

```markdown
- [x] Color picker and color strokes — O[ ] S[ ]
```

Add a new line directly below:

```markdown
- [x] Color in sculpt mode (per-stroke surface color shared with 2D activeColor) — O[ ] S[ ]
```

- [ ] **Step 3: Commit TODO update**

```bash
git add TODO.md
git commit -m "docs: mark color-in-sculpt done in TODO"
```

- [ ] **Step 4: Update auto-memory**

Edit `/Users/alexandre/.claude/projects/-Users-alexandre-documents-copy-code-pensculpt/memory/project_priorities.md`:

- Move "Cor no sculpt" out of "Próximo (alta prioridade)" into "Concluído"
- Promote "Tooltips no hover da Pencil" to position 1 of "Próximo (alta prioridade)"
- Update the date stamp at the top of the file to today

Edit `/Users/alexandre/.claude/projects/-Users-alexandre-documents-copy-code-pensculpt/memory/color_picker_status.md` to note that sculpt-mode colored strokes shipped on `alexandre` on 2026-04-29 (no longer a deferred follow-up).

Update the corresponding pointer descriptions in `MEMORY.md` to reflect the new state.

(No commit — auto-memory lives outside the repo.)

---

## Self-Review Notes

- **Spec coverage:** All 6 spec sections have tasks (Modelo→Task 1; simd4→Task 2; Propagação→Tasks 6, 7, 8; Renderização→Task 5; UI swatch→Task 7; projectTo2D→Task 3; reprojected→Task 4; testes→Tasks 1-4).
- **Type consistency:** `currentStrokeColor` (renderer) and `activeColor` (Coordinator + MetalCanvasView + SculptScreen) are stable across tasks. `simd4(opacity:)` signature consistent. `CodableColor.black` reused as default everywhere.
- **Build-red interlude:** Task 7 deliberately leaves the build broken (SculptScreen requires new args). Task 8 closes it. This is acceptable for a planned multi-step refactor of a public initializer; an executor running tasks sequentially never has more than one task's worth of red.
- **No new shaders:** confirmed by reading SculptRenderer.swift — fragment shader already accepts color via per-vertex buffer.
