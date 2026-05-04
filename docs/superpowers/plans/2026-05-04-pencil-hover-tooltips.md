# Pencil Hover Tooltips Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add hover/long-press tooltips to ~15 toolbar buttons across DrawingScreen and SculptScreen, with a global on/off toggle persisted in `@AppStorage`.

**Architecture:** Centralized `TooltipID` enum (every covered button has a case → `TooltipContent`), a `.tooltip(_:)` ViewModifier that wires `onContinuousHover` + `onLongPressGesture`, and a `TooltipsToggleButton` placed in DrawingScreen nav bar and SculptScreen toolbar.

**Tech Stack:** SwiftUI, iOS 17.0, `@AppStorage`, `.popover` with `presentationCompactAdaptation(.popover)`, XCTest for unit tests.

**Spec:** `docs/superpowers/specs/2026-05-04-pencil-hover-tooltips-design.md`

---

## File Structure

New directory: `PenSculpt/Views/Tooltips/`

| File | Purpose |
|------|---------|
| `PenSculpt/Views/Tooltips/TooltipID.swift` | Enum of all tooltip IDs + `TooltipContent` struct + content map |
| `PenSculpt/Views/Tooltips/TooltipModifier.swift` | `View.tooltip(_:)` modifier + `TooltipView` |
| `PenSculpt/Views/Tooltips/TooltipsToggleButton.swift` | Toggle button (`?` icon) wired to `@AppStorage` |
| `PenSculptTests/TooltipIDTests.swift` | Unit tests for enum coverage |

Modifications:
- `PenSculpt/Views/FloatingToolbar.swift` — add `.tooltip(...)` to each button
- `PenSculpt/Views/DrawingScreen.swift` — add `.tooltip(...)` to nav bar + drawModeControls + toolbar toggle button; embed `TooltipsToggleButton` in nav bar
- `PenSculpt/Views/SculptScreen.swift` — add `.tooltip(...)` to all toolbar buttons; embed `TooltipsToggleButton` in topLeading overlay

---

## Tooltip Text Content (English)

Reference table — used in Task 1 to populate `TooltipID.content`. Strings are final unless review changes them.

| Case | Title | Subtitle |
|------|-------|-------------|
| `colorSwatch` | "Color" | "Tap to change the active drawing color" |
| `undo` | "Undo" | nil |
| `redo` | "Redo" | nil |
| `toolPen` | "Pen" | "Draw with the pen tool" |
| `toolEraser` | "Eraser" | "Erase whole strokes" |
| `toolPixelEraser` | "Pixel eraser" | "Erase parts of strokes pixel by pixel" |
| `clear` | "Clear" | "Remove all strokes from the canvas" |
| `exportImage` | "Share" | "Export the drawing as an image" |
| `toolbarCollapse` | "Toolbar" | "Show or hide the drawing toolbar" |
| `modeToggle` | "Selection mode" | "Switch between drawing and lasso selection" |
| `autosaveToggle` | "Autosave" | "Save changes automatically as you draw" |
| `save` | "Save" | nil |
| `tooltipsToggle` | "Tooltips" | "Show or hide button hints on hover" |
| `sculptClose` | "Close" | "Return to the 2D canvas" |
| `sculptReinfer` | "Re-infer shape" | "Rebuild the 3D shape from the current strokes" |
| `sculptReinferMorph` | "Morph re-infer (beta)" | "Smoothly morph the current shape into the re-inferred one" |
| `sculptAutoProject` | "Auto-project strokes" | "Bring surface strokes back to 2D on exit" |
| `sculptExport` | "Share" | "Export an image or 3D mesh" |
| `sculptColorSwatch` | "Color" | "Active color for new surface strokes" |
| `sculptSurfaceSpace` | "Stroke space" | "Toggle strokes anchored to the surface or to the screen" |
| `sculptRotate` | "Rotate" | "Hold and drag to rotate the 3D view" |
| `sculptEraser` | "Eraser / Smoother" | "Erases strokes; while in deform mode, smooths the surface" |
| `sculptDeform` | "Deform" | "Push and pull the 3D surface with the Pencil" |

---

## Task 1: `TooltipID` enum and `TooltipContent` struct

**Files:**
- Create: `PenSculpt/Views/Tooltips/TooltipID.swift`
- Test: `PenSculptTests/TooltipIDTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PenSculptTests/TooltipIDTests.swift`:

```swift
import XCTest
@testable import PenSculpt

final class TooltipIDTests: XCTestCase {
    func testEveryCaseHasNonEmptyTitle() {
        for id in TooltipID.allCases {
            XCTAssertFalse(id.content.title.isEmpty, "TooltipID.\(id) has empty title")
        }
    }

    func testTitlesAreNotPlaceholders() {
        for id in TooltipID.allCases {
            let title = id.content.title
            XCTAssertFalse(title.uppercased().contains("TODO"), "TooltipID.\(id) title is a placeholder: \(title)")
            XCTAssertFalse(title.uppercased().contains("TBD"), "TooltipID.\(id) title is a placeholder: \(title)")
        }
    }

    func testSubtitlesWhenPresentAreNonEmpty() {
        for id in TooltipID.allCases {
            if let subtitle = id.content.subtitle {
                XCTAssertFalse(subtitle.isEmpty, "TooltipID.\(id) subtitle is empty string (use nil instead)")
            }
        }
    }

    func testCasesAreUnique() {
        let raws = TooltipID.allCases.map(\.rawValue)
        XCTAssertEqual(Set(raws).count, raws.count, "Duplicate raw values in TooltipID")
    }
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run from project root:

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -only-testing:PenSculptTests/TooltipIDTests
```

Expected: build fails ("Cannot find 'TooltipID'"). That's the desired failing state.

- [ ] **Step 3: Implement `TooltipID` and `TooltipContent`**

Create `PenSculpt/Views/Tooltips/TooltipID.swift`:

```swift
import Foundation

struct TooltipContent: Equatable {
    let title: String
    let subtitle: String?
}

enum TooltipID: String, CaseIterable {
    // Drawing — FloatingToolbar
    case colorSwatch
    case undo
    case redo
    case toolPen
    case toolEraser
    case toolPixelEraser
    case clear
    case exportImage

    // Drawing — overlay
    case toolbarCollapse

    // Drawing — nav bar
    case modeToggle
    case autosaveToggle
    case save

    // Shared
    case tooltipsToggle

    // Sculpt — toolbar topLeading
    case sculptClose
    case sculptReinfer
    case sculptReinferMorph
    case sculptAutoProject
    case sculptExport

    // Sculpt — bottom toolbar
    case sculptColorSwatch
    case sculptSurfaceSpace

    // Sculpt — corners
    case sculptRotate
    case sculptEraser
    case sculptDeform

    var content: TooltipContent {
        switch self {
        case .colorSwatch:        return .init(title: "Color", subtitle: "Tap to change the active drawing color")
        case .undo:               return .init(title: "Undo", subtitle: nil)
        case .redo:               return .init(title: "Redo", subtitle: nil)
        case .toolPen:            return .init(title: "Pen", subtitle: "Draw with the pen tool")
        case .toolEraser:         return .init(title: "Eraser", subtitle: "Erase whole strokes")
        case .toolPixelEraser:    return .init(title: "Pixel eraser", subtitle: "Erase parts of strokes pixel by pixel")
        case .clear:              return .init(title: "Clear", subtitle: "Remove all strokes from the canvas")
        case .exportImage:        return .init(title: "Share", subtitle: "Export the drawing as an image")
        case .toolbarCollapse:    return .init(title: "Toolbar", subtitle: "Show or hide the drawing toolbar")
        case .modeToggle:         return .init(title: "Selection mode", subtitle: "Switch between drawing and lasso selection")
        case .autosaveToggle:     return .init(title: "Autosave", subtitle: "Save changes automatically as you draw")
        case .save:               return .init(title: "Save", subtitle: nil)
        case .tooltipsToggle:     return .init(title: "Tooltips", subtitle: "Show or hide button hints on hover")
        case .sculptClose:        return .init(title: "Close", subtitle: "Return to the 2D canvas")
        case .sculptReinfer:      return .init(title: "Re-infer shape", subtitle: "Rebuild the 3D shape from the current strokes")
        case .sculptReinferMorph: return .init(title: "Morph re-infer (beta)", subtitle: "Smoothly morph the current shape into the re-inferred one")
        case .sculptAutoProject:  return .init(title: "Auto-project strokes", subtitle: "Bring surface strokes back to 2D on exit")
        case .sculptExport:       return .init(title: "Share", subtitle: "Export an image or 3D mesh")
        case .sculptColorSwatch:  return .init(title: "Color", subtitle: "Active color for new surface strokes")
        case .sculptSurfaceSpace: return .init(title: "Stroke space", subtitle: "Toggle strokes anchored to the surface or to the screen")
        case .sculptRotate:       return .init(title: "Rotate", subtitle: "Hold and drag to rotate the 3D view")
        case .sculptEraser:       return .init(title: "Eraser / Smoother", subtitle: "Erases strokes; while in deform mode, smooths the surface")
        case .sculptDeform:       return .init(title: "Deform", subtitle: "Push and pull the 3D surface with the Pencil")
        }
    }
}
```

- [ ] **Step 4: Regenerate Xcode project (xcodegen picks up new directory)**

```bash
xcodegen generate
```

Expected: "Generated project successfully" or no errors.

- [ ] **Step 5: Run tests, verify they pass**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -only-testing:PenSculptTests/TooltipIDTests
```

Expected: 4 tests passed.

- [ ] **Step 6: Commit**

```bash
git add PenSculpt/Views/Tooltips/TooltipID.swift PenSculptTests/TooltipIDTests.swift PenSculpt.xcodeproj
git commit -m "feat(tooltips): add TooltipID enum with content map"
```

---

## Task 2: `TooltipModifier` and `TooltipView`

SwiftUI gesture-driven UI is hard to drive in unit tests; this task is verified visually in Task 6. Build success is the automated gate.

**Files:**
- Create: `PenSculpt/Views/Tooltips/TooltipModifier.swift`

- [ ] **Step 1: Implement modifier and view**

Create `PenSculpt/Views/Tooltips/TooltipModifier.swift`:

```swift
import SwiftUI

struct TooltipView: View {
    let content: TooltipContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title)
                .font(.callout.weight(.medium))
            if let subtitle = content.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 240, alignment: .leading)
    }
}

struct TooltipModifier: ViewModifier {
    let id: TooltipID
    @AppStorage("tooltipsEnabled") private var tooltipsEnabled = true
    @State private var isShowing = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var longPressDismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                guard tooltipsEnabled else { return }
                handleHover(phase)
            }
            .onLongPressGesture(minimumDuration: 0.5) {
                guard tooltipsEnabled else { return }
                showFromLongPress()
            }
            .popover(isPresented: $isShowing) {
                TooltipView(content: id.content)
                    .presentationCompactAdaptation(.popover)
            }
    }

    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active:
            hoverTask?.cancel()
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { isShowing = true }
            }
        case .ended:
            hoverTask?.cancel()
            hoverTask = nil
            withAnimation(.easeOut(duration: 0.1)) { isShowing = false }
        }
    }

    private func showFromLongPress() {
        longPressDismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { isShowing = true }
        longPressDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.1)) { isShowing = false }
        }
    }
}

extension View {
    func tooltip(_ id: TooltipID) -> some View {
        modifier(TooltipModifier(id: id))
    }
}
```

- [ ] **Step 2: Regenerate project and build**

```bash
xcodegen generate && xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/Views/Tooltips/TooltipModifier.swift PenSculpt.xcodeproj
git commit -m "feat(tooltips): add TooltipModifier and TooltipView"
```

---

## Task 3: `TooltipsToggleButton`

**Files:**
- Create: `PenSculpt/Views/Tooltips/TooltipsToggleButton.swift`

- [ ] **Step 1: Implement the button**

Create `PenSculpt/Views/Tooltips/TooltipsToggleButton.swift`:

```swift
import SwiftUI

struct TooltipsToggleButton: View {
    @AppStorage("tooltipsEnabled") private var tooltipsEnabled = true

    var body: some View {
        Button {
            tooltipsEnabled.toggle()
        } label: {
            Image(systemName: tooltipsEnabled ? "questionmark.circle.fill" : "questionmark.circle")
                .font(.body)
                .foregroundStyle(tooltipsEnabled ? .blue : .secondary)
        }
        .tooltip(.tooltipsToggle)
    }
}
```

- [ ] **Step 2: Regenerate project and build**

```bash
xcodegen generate && xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/Views/Tooltips/TooltipsToggleButton.swift PenSculpt.xcodeproj
git commit -m "feat(tooltips): add TooltipsToggleButton"
```

---

## Task 4: Apply tooltips to DrawingScreen

Wires every covered button in `FloatingToolbar.swift` and `DrawingScreen.swift` and adds the toggle button to the nav bar.

**Files:**
- Modify: `PenSculpt/Views/FloatingToolbar.swift`
- Modify: `PenSculpt/Views/DrawingScreen.swift`

- [ ] **Step 1: Edit `FloatingToolbar.swift`**

Apply `.tooltip(...)` to each button. The full updated body:

```swift
HStack(spacing: 12) {
    Button { showColorPopover = true } label: {
        Circle()
            .fill(Color(activeColor))
            .frame(width: 28, height: 28)
            .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
    }
    .tooltip(.colorSwatch)
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
        .tooltip(.undo)
    Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
        .tooltip(.redo)

    Divider().frame(height: 24)

    ForEach(DrawingTool.allCases, id: \.self) { tool in
        Button {
            selectedTool = tool
        } label: {
            Image(systemName: tool.iconName)
                .foregroundStyle(selectedTool == tool ? .primary : .secondary)
        }
        .tooltip(tooltipID(for: tool))
    }

    Divider().frame(height: 24)

    Button(action: onClear) { Image(systemName: "trash") }
        .tooltip(.clear)
    Button(action: onExport) { Image(systemName: "square.and.arrow.up") }
        .tooltip(.exportImage)
}
```

Add helper at the bottom of `FloatingToolbar` (before closing brace of the struct):

```swift
private func tooltipID(for tool: DrawingTool) -> TooltipID {
    switch tool {
    case .pen: return .toolPen
    case .eraser: return .toolEraser
    case .pixelEraser: return .toolPixelEraser
    }
}
```

- [ ] **Step 2: Edit `DrawingScreen.swift` — `navBarItems`**

Replace `navBarItems` (currently lines 122–149) with:

```swift
private var navBarItems: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
        HStack(spacing: 12) {
            TooltipsToggleButton()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { vm.toggleMode() }
            } label: {
                Image(systemName: vm.appMode == .draw ? "lasso" : "pencil.tip")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .tooltip(.modeToggle)

            Button {
                withAnimation { vm.autosaveEnabled.toggle() }
            } label: {
                Image(systemName: vm.autosaveEnabled
                      ? "arrow.triangle.2.circlepath.circle.fill"
                      : "arrow.triangle.2.circlepath.circle")
                    .font(.body)
                    .foregroundStyle(vm.autosaveEnabled ? .primary : .secondary)
            }
            .tooltip(.autosaveToggle)

            Button { saveToDocument() } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.body)
            }
            .tooltip(.save)
        }
    }
}
```

- [ ] **Step 3: Edit `DrawingScreen.swift` — `drawModeControls` toolbar collapse button**

In `drawModeControls`, append `.tooltip(.toolbarCollapse)` to the chevron/ellipsis Button (currently lines 189–197):

```swift
Button {
    withAnimation(.easeInOut(duration: 0.2)) { vm.showToolbar.toggle() }
} label: {
    Image(systemName: vm.showToolbar ? "chevron.down.circle.fill" : "ellipsis.circle")
        .font(.title2)
        .padding(12)
        .background(.ultraThinMaterial, in: Circle())
}
.tooltip(.toolbarCollapse)
.padding(.bottom, 16)
```

- [ ] **Step 4: Build**

```bash
xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Run full test suite to ensure nothing regressed**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

Expected: all tests pass (no behavior changed, only modifiers added).

- [ ] **Step 6: Commit**

```bash
git add PenSculpt/Views/FloatingToolbar.swift PenSculpt/Views/DrawingScreen.swift
git commit -m "feat(tooltips): apply tooltips to DrawingScreen buttons"
```

---

## Task 5: Apply tooltips to SculptScreen

Wires every covered button in `SculptScreen.swift` and adds the toggle button to the topLeading toolbar.

**Files:**
- Modify: `PenSculpt/Views/SculptScreen.swift`

- [ ] **Step 1: Edit topLeading toolbar overlay (lines 67–124)**

Replace the topLeading overlay block with:

```swift
.overlay(alignment: .topLeading) {
    HStack(spacing: 12) {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .tooltip(.sculptClose)

        Button(action: reInfer) {
            if isReInferring {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isReInferring)
        .tooltip(.sculptReinfer)

        Button(action: reInferMorph) {
            if isReInferring {
                ProgressView()
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.title3)
                    Text("beta")
                        .font(.system(size: 8))
                }
                .foregroundStyle(.secondary)
            }
        }
        .disabled(isReInferring)
        .tooltip(.sculptReinferMorph)

        Button {
            autoProjectStrokes.toggle()
        } label: {
            Image(systemName: autoProjectStrokes ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(autoProjectStrokes ? .blue : .secondary)
        }
        .tooltip(.sculptAutoProject)

        Button {
            showFormatDialog = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
        .tooltip(.sculptExport)

        TooltipsToggleButton()
    }
    .padding()
}
```

- [ ] **Step 2: Edit bottom overlay (lines 135–171)**

Replace the bottom overlay block with:

```swift
.overlay(alignment: .bottom) {
    HStack(spacing: 12) {
        Button { showColorPopover = true } label: {
            Circle()
                .fill(Color(activeColor))
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(Color.primary.opacity(0.4), lineWidth: 1))
        }
        .tooltip(.sculptColorSwatch)
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
        .tooltip(.sculptSurfaceSpace)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    .padding(.bottom, 20)
}
```

Note: the existing `.help(...)` modifier on the surface/space button is removed — `.tooltip(.sculptSurfaceSpace)` replaces it.

- [ ] **Step 3: Edit bottomLeading rotate badge (lines 172–184)**

The rotate "button" is currently an `Image` with a `DragGesture`, not a `Button`. Wrap with `.tooltip(.sculptRotate)`:

```swift
.overlay(alignment: .bottomLeading) {
    Image(systemName: isRotateMode ? "rotate.3d.fill" : "rotate.3d")
        .font(.title)
        .foregroundStyle(isRotateMode ? .blue : .secondary)
        .frame(width: 60, height: 60)
        .background(.ultraThinMaterial, in: Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isRotateMode = true }
                .onEnded { _ in isRotateMode = false }
        )
        .tooltip(.sculptRotate)
        .padding(20)
}
```

Note: rotate uses a `DragGesture` that fires on touch-down. The tooltip's long-press fallback (0.5s) will conflict — long-press will set `isRotateMode = true` first, and after 0.5s the tooltip will appear while rotate is active. This is acceptable: hover still works cleanly on Pencil; long-press fallback on the rotate badge is degraded but not broken. If it proves annoying in manual verification, scope `.tooltip` only to hover for this control by passing a custom flag (deferred to a follow-up).

- [ ] **Step 4: Edit bottomTrailing eraser/deform overlay (lines 185–222)**

Replace with:

```swift
.overlay(alignment: .bottomTrailing) {
    HStack(spacing: 12) {
        Button {
            if isDeformMode {
                isSmoothMode.toggle()
            } else {
                isEraseStrokeMode.toggle()
            }
        } label: {
            let active = isDeformMode ? isSmoothMode : isEraseStrokeMode
            Image(systemName: active ? "eraser.fill" : "eraser")
                .font(.title2)
                .foregroundStyle(active ? .mint : .secondary)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
        }
        .tooltip(.sculptEraser)

        Button {
            if isDeformMode {
                isDeformMode = false
                isSmoothMode = false
                brushOpacity = savedDrawOpacity
            } else {
                savedDrawOpacity = brushOpacity
                isDeformMode = true
                isEraseStrokeMode = false
                brushOpacity = CGFloat(config.deformDefaultForce)
            }
        } label: {
            Image(systemName: isDeformMode ? "hand.point.up.fill" : "hand.point.up")
                .font(.title)
                .foregroundStyle(isDeformMode ? .orange : .secondary)
                .frame(width: 60, height: 60)
                .background(.ultraThinMaterial, in: Circle())
        }
        .tooltip(.sculptDeform)
    }
    .padding(20)
}
```

- [ ] **Step 5: Build**

```bash
xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run full test suite**

```bash
xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add PenSculpt/Views/SculptScreen.swift
git commit -m "feat(tooltips): apply tooltips to SculptScreen buttons"
```

---

## Task 6: Manual verification on iPad

Automated tests cover the data layer (TooltipID coverage). Hover and gesture behavior require real hardware.

**Pre-conditions:** iPad with hover-capable Pencil (Pencil Pro or Pencil 2nd gen on M2+ iPad Pro), connected and trusted.

- [ ] **Step 1: Build & run on connected iPad**

In Xcode, select the connected iPad as run destination, then ⌘R. (If asked, sign with the existing development team `926MRS7WCP`.)

- [ ] **Step 2: DrawingScreen — hover behavior**

For each button in the FloatingToolbar (color swatch, undo, redo, pen, eraser, pixel eraser, clear, share) and each nav bar button (tooltips toggle, mode toggle, autosave toggle, save) and the toolbar collapse button:

- Hover Pencil ~1cm above the button. Tooltip should appear after ~400ms with the expected title and (where defined) subtitle.
- Move Pencil away. Tooltip should disappear immediately.
- Tap normally with Pencil or finger. The button's normal action must still fire.

Mark any button whose tooltip text reads wrong or unclear.

- [ ] **Step 3: DrawingScreen — long-press fallback**

For each button: long-press with finger for ~0.5s. The tooltip should appear and stay ~2s, then dismiss. Releasing earlier than 0.5s should NOT show the tooltip and should fire the tap.

Note: `Button` consumes long-press internally if it's not registered, so taps still work; if any button fires its action AND shows a tooltip, that's a conflict to flag.

- [ ] **Step 4: SculptScreen — hover behavior**

Repeat Step 2 for SculptScreen: close, re-infer, sparkles, auto-project, share, color swatch, surface/space, eraser/smoother, deform, rotate, tooltips toggle.

For the **rotate badge**, a long-press will trigger rotate mode AND show the tooltip — note this as expected per spec risk note. Hover-only behavior on rotate should be clean.

- [ ] **Step 5: Toggle behavior**

- Tap the `?` button in DrawingScreen nav bar. Icon switches to outlined. Hover/long-press now do nothing on every button.
- Force-quit and relaunch the app. The toggle remains off (verifies `@AppStorage` persistence).
- Tap the `?` button again. Tooltips return.
- Open SculptScreen. The `?` button there reflects the same state.

- [ ] **Step 6: Off-screen safety**

For buttons near screen edges (color swatch on the bottom toolbar; close button at top-leading): hover and verify the tooltip auto-positions and never gets clipped.

- [ ] **Step 7: Mark verification done**

If any issues found, file targeted fixes (do NOT commit ad-hoc workarounds without going back through the task list).

If all checks pass:

```bash
git status   # should be clean
```

End of plan.

---

## Out of scope (do not implement here)

- Localization of tooltip strings.
- Tooltips on `BrushControls`, inside `ColorPickerPopover`, on confirmation dialogs.
- User-configurable hover delay.
- Animation polish beyond fade.
- Keyboard shortcut hints in tooltip text.
- Tooltips on the rotate gesture limiting to hover-only (deferred unless manual verification flags it).
