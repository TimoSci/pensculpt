# Color Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a global active color with fixed presets, a per-document recents history, and access to the native `ColorPicker`, and make 2D drawing use it.

**Architecture:** Extend `Canvas` with `activeColor` and `recentColors` so they persist inside `.pensculpt` and get undo for free. Route all changes through a single `DrawingViewModel.setActiveColor(_:addToRecents:)` entry point. `CanvasView` reads `activeColor` and builds `PKInkingTool` with it. A new `ColorPickerPopover` view is attached to a swatch button in `FloatingToolbar`.

**Tech Stack:** Swift, SwiftUI, PencilKit, XCTest.

**Spec:** `docs/superpowers/specs/2026-04-13-color-picker-design.md`

---

## File Map

- **Modify:** `PenSculpt/Models/Canvas.swift` — add `activeColor`, `recentColors`, `pushRecentColor(_:)`.
- **Modify:** `PenSculpt/Models/Stroke.swift` — add `CodableColor.uiColor(withAlpha:)` helper.
- **Modify:** `PenSculpt/Views/DrawingViewModel.swift` — add `setActiveColor(_:addToRecents:)`.
- **Modify:** `PenSculpt/Drawing/CanvasView.swift` — consume an `activeColor: CodableColor` parameter for `PKInkingTool`.
- **Create:** `PenSculpt/Views/ColorPickerPopover.swift` — the popover UI (presets grid, recents row, Personalizar button).
- **Modify:** `PenSculpt/Views/FloatingToolbar.swift` — add swatch button that presents the popover.
- **Modify:** `PenSculpt/Views/DrawingScreen.swift` — wire bindings from `vm` to `FloatingToolbar` and `CanvasView`, register color-change undo.
- **Modify:** `PenSculptTests/CanvasTests.swift` — defaults, Codable round-trip, recents dedupe/cap.
- **Modify:** `PenSculptTests/DrawingViewModelTests.swift` — `setActiveColor` behavior (preset vs custom).

---

## Task 1: Extend `Canvas` model with color state

**Files:**
- Modify: `PenSculpt/Models/Canvas.swift`
- Test: `PenSculptTests/CanvasTests.swift`

- [ ] **Step 1: Write failing tests for defaults and recents behavior**

Append to `PenSculptTests/CanvasTests.swift`:

```swift
    func testDefaultActiveColorIsBlack() {
        let canvas = Canvas()
        XCTAssertEqual(canvas.activeColor, .black)
        XCTAssertTrue(canvas.recentColors.isEmpty)
    }

    func testPushRecentColorPrependsAndDedupes() {
        var canvas = Canvas()
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CodableColor(red: 0, green: 0, blue: 1, alpha: 1)
        canvas.pushRecentColor(red)
        canvas.pushRecentColor(blue)
        canvas.pushRecentColor(red) // should move red to front, not duplicate
        XCTAssertEqual(canvas.recentColors, [red, blue])
    }

    func testPushRecentColorCapsAtSix() {
        var canvas = Canvas()
        for i in 0..<8 {
            let c = CodableColor(red: CGFloat(i) / 10, green: 0, blue: 0, alpha: 1)
            canvas.pushRecentColor(c)
        }
        XCTAssertEqual(canvas.recentColors.count, 6)
        // Most recent first — last pushed (i=7) should be at index 0
        XCTAssertEqual(canvas.recentColors.first,
                       CodableColor(red: 0.7, green: 0, blue: 0, alpha: 1))
    }

    func testCodableRoundTripsColorState() throws {
        var canvas = Canvas()
        canvas.activeColor = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        canvas.pushRecentColor(CodableColor(red: 1, green: 0, blue: 0, alpha: 1))
        let data = try JSONEncoder().encode(canvas)
        let decoded = try JSONDecoder().decode(Canvas.self, from: data)
        XCTAssertEqual(decoded.activeColor, canvas.activeColor)
        XCTAssertEqual(decoded.recentColors, canvas.recentColors)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run from project root:
```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' -only-testing:PenSculptTests/CanvasTests 2>&1 | tail -30
```
Expected: build failure (`activeColor` / `recentColors` / `pushRecentColor` don't exist).

- [ ] **Step 3: Add the fields and helper to `Canvas`**

Replace the body of `PenSculpt/Models/Canvas.swift` with:

```swift
import Foundation

struct Canvas: Codable, Equatable, Sendable {
    static let maxRecentColors = 6

    var size: CGSize
    var strokes: [Stroke]
    var activeColor: CodableColor
    var recentColors: [CodableColor]

    init(size: CGSize = CGSize(width: 1024, height: 1366)) {
        self.size = size
        self.strokes = []
        self.activeColor = .black
        self.recentColors = []
    }

    private enum CodingKeys: String, CodingKey {
        case size, strokes, activeColor, recentColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decode(CGSize.self, forKey: .size)
        strokes = try container.decode([Stroke].self, forKey: .strokes)
        activeColor = try container.decodeIfPresent(CodableColor.self, forKey: .activeColor) ?? .black
        recentColors = try container.decodeIfPresent([CodableColor].self, forKey: .recentColors) ?? []
    }

    mutating func addStroke(_ stroke: Stroke) {
        strokes.append(stroke)
    }

    mutating func removeStroke(id: UUID) {
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes.remove(at: index)
        }
    }

    mutating func clearStrokes() {
        strokes.removeAll()
    }

    mutating func pushRecentColor(_ color: CodableColor) {
        recentColors.removeAll { $0 == color }
        recentColors.insert(color, at: 0)
        if recentColors.count > Self.maxRecentColors {
            recentColors = Array(recentColors.prefix(Self.maxRecentColors))
        }
    }
}
```

Note: custom `init(from:)` keeps old `.pensculpt` files decodable by defaulting the new fields.

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' -only-testing:PenSculptTests/CanvasTests 2>&1 | tail -30
```
Expected: all `CanvasTests` pass.

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Models/Canvas.swift PenSculptTests/CanvasTests.swift
git commit -m "feat(canvas): persist active color and recents"
```

---

## Task 2: `CodableColor.uiColor` helper

**Files:**
- Modify: `PenSculpt/Models/Stroke.swift`
- Test: `PenSculptTests/StrokeTests.swift`

- [ ] **Step 1: Write failing test**

Append to `PenSculptTests/StrokeTests.swift`:

```swift
    func testCodableColorUIColorAppliesOpacityMultiplier() {
        let color = CodableColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.8)
        let ui = color.uiColor(opacityMultiplier: 0.5)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.25, accuracy: 0.001)
        XCTAssertEqual(g, 0.5, accuracy: 0.001)
        XCTAssertEqual(b, 0.75, accuracy: 0.001)
        XCTAssertEqual(a, 0.4, accuracy: 0.001) // 0.8 * 0.5
    }
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' -only-testing:PenSculptTests/StrokeTests 2>&1 | tail -30
```
Expected: build failure (`uiColor(opacityMultiplier:)` doesn't exist).

- [ ] **Step 3: Add helper**

Add this extension at the end of `PenSculpt/Models/Stroke.swift`:

```swift
#if canImport(UIKit)
import UIKit

extension CodableColor {
    func uiColor(opacityMultiplier: CGFloat = 1) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha * opacityMultiplier)
    }
}
#endif
```

- [ ] **Step 4: Run test to verify it passes**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' -only-testing:PenSculptTests/StrokeTests 2>&1 | tail -30
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Models/Stroke.swift PenSculptTests/StrokeTests.swift
git commit -m "feat(stroke): add CodableColor uiColor helper"
```

---

## Task 3: `DrawingViewModel.setActiveColor`

**Files:**
- Modify: `PenSculpt/Views/DrawingViewModel.swift`
- Test: `PenSculptTests/DrawingViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Append to `PenSculptTests/DrawingViewModelTests.swift`:

```swift
    func testSetActiveColorPresetDoesNotTouchRecents() {
        let vm = DrawingViewModel(canvas: Canvas())
        let red = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        vm.setActiveColor(red, addToRecents: false)
        XCTAssertEqual(vm.canvas.activeColor, red)
        XCTAssertTrue(vm.canvas.recentColors.isEmpty)
    }

    func testSetActiveColorCustomPushesRecents() {
        let vm = DrawingViewModel(canvas: Canvas())
        let teal = CodableColor(red: 0, green: 0.5, blue: 0.5, alpha: 1)
        vm.setActiveColor(teal, addToRecents: true)
        XCTAssertEqual(vm.canvas.activeColor, teal)
        XCTAssertEqual(vm.canvas.recentColors, [teal])
    }

    func testSetActiveColorCustomDedupesRecents() {
        let vm = DrawingViewModel(canvas: Canvas())
        let a = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let b = CodableColor(red: 0, green: 1, blue: 0, alpha: 1)
        vm.setActiveColor(a, addToRecents: true)
        vm.setActiveColor(b, addToRecents: true)
        vm.setActiveColor(a, addToRecents: true)
        XCTAssertEqual(vm.canvas.recentColors, [a, b])
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' -only-testing:PenSculptTests/DrawingViewModelTests 2>&1 | tail -30
```
Expected: build failure (`setActiveColor` doesn't exist).

- [ ] **Step 3: Add method**

In `PenSculpt/Views/DrawingViewModel.swift`, after the `clearStrokes()` method (around line 85), add:

```swift
    // MARK: - Color

    func setActiveColor(_ color: CodableColor, addToRecents: Bool) {
        canvas.activeColor = color
        if addToRecents {
            canvas.pushRecentColor(color)
        }
    }
```

- [ ] **Step 4: Run to verify they pass**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' -only-testing:PenSculptTests/DrawingViewModelTests 2>&1 | tail -30
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Views/DrawingViewModel.swift PenSculptTests/DrawingViewModelTests.swift
git commit -m "feat(vm): add setActiveColor entry point"
```

---

## Task 4: `CanvasView` consumes active color

**Files:**
- Modify: `PenSculpt/Drawing/CanvasView.swift`

- [ ] **Step 1: Add the `activeColor` parameter**

In `PenSculpt/Drawing/CanvasView.swift`, update the struct properties (after `strokeOpacity` at line 8):

```swift
    var activeColor: CodableColor
```

Replace the `pen` case in `pkTool(for:)` (currently CanvasView.swift:50-51):

```swift
        case .pen:
            let uiColor = activeColor.uiColor(opacityMultiplier: strokeOpacity)
            return PKInkingTool(.pen, color: uiColor, width: strokeWidth)
```

- [ ] **Step 2: Update call site in `DrawingScreen`**

In `PenSculpt/Views/DrawingScreen.swift`, update `canvasLayer` (CanvasView.swift:131) to pass the new parameter:

```swift
    private var canvasLayer: some View {
        CanvasView(
            drawing: $pkDrawing,
            selectedTool: vm.selectedTool,
            strokeWidth: vm.strokeWidth,
            strokeOpacity: vm.strokeOpacity,
            activeColor: vm.canvas.activeColor,
            onStrokeCompleted: { addStrokeWithUndo(StrokeConverter.convert($0)) },
            onStrokeErased: { handleErase($0) },
            isInteractive: vm.appMode == .draw,
            viewBridge: viewBridge
        )
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .pencilDoubleTap)) { _ in
            vm.handlePencilDoubleTap()
        }
    }
```

- [ ] **Step 3: Build**

```bash
xcodebuild build -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PenSculpt/Drawing/CanvasView.swift PenSculpt/Views/DrawingScreen.swift
git commit -m "feat(canvas-view): use active color for pen tool"
```

---

## Task 5: `ColorPickerPopover` view

**Files:**
- Create: `PenSculpt/Views/ColorPickerPopover.swift`

- [ ] **Step 1: Create the popover view**

Create `PenSculpt/Views/ColorPickerPopover.swift` with:

```swift
import SwiftUI

struct ColorPickerPopover: View {
    let activeColor: CodableColor
    let recentColors: [CodableColor]
    var onSelectPreset: (CodableColor) -> Void
    var onSelectCustom: (CodableColor) -> Void

    @State private var customColor: Color = .black
    @Environment(\.dismiss) private var dismiss

    static let presets: [CodableColor] = [
        CodableColor(red: 0.00, green: 0.00, blue: 0.00, alpha: 1), // black
        CodableColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1), // white
        CodableColor(red: 0.70, green: 0.70, blue: 0.70, alpha: 1), // light gray
        CodableColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1), // dark gray
        CodableColor(red: 0.90, green: 0.15, blue: 0.15, alpha: 1), // red
        CodableColor(red: 0.95, green: 0.55, blue: 0.10, alpha: 1), // orange
        CodableColor(red: 0.98, green: 0.85, blue: 0.15, alpha: 1), // yellow
        CodableColor(red: 0.25, green: 0.75, blue: 0.30, alpha: 1), // green
        CodableColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 1), // blue
        CodableColor(red: 0.60, green: 0.25, blue: 0.85, alpha: 1), // purple
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Presets")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Self.presets, id: \.self) { preset in
                    swatch(for: preset)
                        .onTapGesture {
                            onSelectPreset(preset)
                            dismiss()
                        }
                }
            }

            if !recentColors.isEmpty {
                Text("Recentes")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(recentColors, id: \.self) { color in
                        swatch(for: color)
                            .onTapGesture {
                                onSelectCustom(color)
                                dismiss()
                            }
                    }
                    Spacer()
                }
            }

            Divider()

            ColorPicker("Personalizar…", selection: $customColor, supportsOpacity: true)
                .onChange(of: customColor) { _, newValue in
                    onSelectCustom(CodableColor(newValue))
                }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear { customColor = Color(activeColor) }
    }

    private func swatch(for color: CodableColor) -> some View {
        Circle()
            .fill(Color(color))
            .frame(width: 32, height: 32)
            .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
            .overlay(
                Circle()
                    .stroke(Color.accentColor, lineWidth: color == activeColor ? 3 : 0)
            )
    }
}

extension CodableColor: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(red); hasher.combine(green); hasher.combine(blue); hasher.combine(alpha)
    }
}

extension Color {
    init(_ c: CodableColor) {
        self.init(.sRGB, red: Double(c.red), green: Double(c.green), blue: Double(c.blue), opacity: Double(c.alpha))
    }
}

extension CodableColor {
    init(_ color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
```

Note: `CodableColor: Hashable` is added here because `ForEach(id: \.self)` needs it. If adding `Hashable` to the existing `struct CodableColor` declaration in `Stroke.swift` is preferred, do that instead and drop the extension here — either location is fine, as long as it's declared exactly once.

- [ ] **Step 2: Build**

```bash
xcodebuild build -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

If `ColorPickerPopover.swift` is not automatically included in the target, add it to `project.yml` (XcodeGen project) and re-run `xcodegen`, or add it via Xcode "Add Files to PenSculpt".

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/Views/ColorPickerPopover.swift project.yml
git commit -m "feat(ui): add color picker popover view"
```

---

## Task 6: Swatch button in `FloatingToolbar`

**Files:**
- Modify: `PenSculpt/Views/FloatingToolbar.swift`

- [ ] **Step 1: Add bindings and swatch button**

Replace the body of `PenSculpt/Views/FloatingToolbar.swift` with:

```swift
import SwiftUI

struct FloatingToolbar: View {
    @Binding var selectedTool: DrawingTool
    @Binding var strokeWidth: CGFloat
    @Binding var strokeOpacity: CGFloat
    let activeColor: CodableColor
    let recentColors: [CodableColor]
    var onSelectPresetColor: (CodableColor) -> Void
    var onSelectCustomColor: (CodableColor) -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    @State private var showColorPopover = false

    var body: some View {
        VStack(spacing: 8) {
            BrushControls(brushSize: $strokeWidth, brushOpacity: $strokeOpacity)
                .padding(.horizontal, 16)

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

                Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }

                Divider().frame(height: 24)

                ForEach(DrawingTool.allCases, id: \.self) { tool in
                    Button {
                        selectedTool = tool
                    } label: {
                        Image(systemName: tool.iconName)
                            .foregroundStyle(selectedTool == tool ? .primary : .secondary)
                    }
                }

                Divider().frame(height: 24)

                Button(action: onClear) { Image(systemName: "trash") }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild build -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' 2>&1 | tail -20
```
Expected: BUILD FAILED — `DrawingScreen` call site is missing the new parameters. Task 7 fixes this.

- [ ] **Step 3: Do not commit yet** — Task 7 completes the call site change so the project builds.

---

## Task 7: Wire `DrawingScreen` bindings and undo

**Files:**
- Modify: `PenSculpt/Views/DrawingScreen.swift`

- [ ] **Step 1: Add the color-change undo helper**

In `PenSculpt/Views/DrawingScreen.swift`, add this method near the other `...WithUndo` helpers (after `addStrokeWithUndo`, around line 213):

```swift
    private func setActiveColorWithUndo(_ color: CodableColor, addToRecents: Bool) {
        let previousActive = vm.canvas.activeColor
        let previousRecents = vm.canvas.recentColors
        vm.setActiveColor(color, addToRecents: addToRecents)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            vm.canvas.activeColor = previousActive
            vm.canvas.recentColors = previousRecents
        }
    }
```

- [ ] **Step 2: Update the `FloatingToolbar` call site**

Replace the `FloatingToolbar(...)` instantiation inside `drawModeControls` (DrawingScreen.swift:150) with:

```swift
            FloatingToolbar(
                selectedTool: $vm.selectedTool,
                strokeWidth: $vm.strokeWidth,
                strokeOpacity: $vm.strokeOpacity,
                activeColor: vm.canvas.activeColor,
                recentColors: vm.canvas.recentColors,
                onSelectPresetColor: { setActiveColorWithUndo($0, addToRecents: false) },
                onSelectCustomColor: { setActiveColorWithUndo($0, addToRecents: true) },
                onUndo: { undoManager?.undo() },
                onRedo: { undoManager?.redo() },
                onClear: { clearWithUndo() }
            )
```

- [ ] **Step 3: Build the project**

```bash
xcodebuild build -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' 2>&1 | tail -20
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Run the full test suite**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro (13-inch) (M4)' 2>&1 | tail -40
```
Expected: all tests pass.

- [ ] **Step 5: Commit Tasks 6 + 7 together**

```bash
git add PenSculpt/Views/FloatingToolbar.swift PenSculpt/Views/DrawingScreen.swift
git commit -m "feat(toolbar): swatch button + undoable color changes"
```

---

## Task 8: Manual verification on device

- [ ] **Step 1: Run on the iPad**

From Xcode, ⌘R on the connected iPad Pro M4 target.

- [ ] **Step 2: Golden-path checks**

In a new document:
- Tap the swatch → popover opens with 10 presets, no recents row, and the Personalizar control.
- Tap a preset (e.g., blue) → popover closes, swatch turns blue, next Pencil stroke is blue. Recents row remains hidden.
- Tap swatch → Personalizar → pick a non-preset color → swatch updates, stroke draws in that color, popover reopen shows the custom color under "Recentes".
- Undo (toolbar undo button) → active color reverts to the previous value. Redo → restores the custom color.
- Save the document, close, reopen → active color and recents are restored exactly.
- Switch to eraser → swatch remains visible but erasing is unaffected by color.

- [ ] **Step 3: Report results**

Note any regressions or UI issues. If everything passes, mark the TODO entry:

In `TODO.md`, change:
```
- [ ] Color picker and color strokes — O[ ] S[ ]
```
to:
```
- [x] Color picker and color strokes — O[ ] S[ ]
```
(Leaves sculpt-mode color strokes as a follow-up, as documented in the spec.)

- [ ] **Step 4: Commit the TODO update**

```bash
git add TODO.md
git commit -m "docs: mark color picker done in TODO"
```

---

## Notes

- Backwards compatibility: existing `.pensculpt` files decode with `activeColor = .black` and empty `recentColors` thanks to the custom `init(from:)` in Task 1.
- Sculpt-mode color strokes are intentionally deferred (see spec §Scope). `SurfaceStroke.projectTo2D()` will still emit blue until that follow-up lands — flag but do not fix here.
- The eraser tools ignore `activeColor` by design.
