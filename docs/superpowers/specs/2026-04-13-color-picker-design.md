# Color Picker — Design

## Goal

Let the user pick a color for drawing. The selected color is global (shared across all current and future drawing tools), persisted per document, and selectable through a compact in-toolbar picker with preset swatches, a recent-colors history, and access to the native SwiftUI `ColorPicker` for custom colors.

## Scope

**In scope**
- `activeColor` and `recentColors` state persisted inside `Canvas` (the existing document model).
- Swatch button on `FloatingToolbar` that opens a popover containing fixed presets, a recents row, and a "Personalizar…" entry to the native `ColorPicker`.
- 2D drawing (`PKCanvasView`) uses `activeColor` for `PKInkingTool` instead of hardcoded black.
- Undo/redo of color changes via the existing `UndoManager` (automatic because the color lives in `Canvas`).

**Out of scope (explicit follow-ups)**
- Colored strokes in sculpt mode. `SurfaceStroke` currently does not store a color, and `SurfaceStroke.projectTo2D()` has a hardcoded blue (`SculptObject.swift:40`). Wiring color into the Metal renderer and into `SurfaceStroke` is a separate task.
- Eraser tools do not show or use color.
- Gradient/intensity eraser feature (discussed during brainstorming) — noted as a future idea; requires deeper refactor of 2D rendering because `PKDrawing` is immutable.

## State and Persistence

Add two fields to `Canvas`:

```swift
var activeColor: CodableColor         // default: .black
var recentColors: [CodableColor]      // default: []
```

- Both are `Codable`, so they persist automatically inside the `.pensculpt` package.
- `recentColors` is capped at **6 entries**, most-recent first, no duplicates.
- Preset swatches (see below) do **not** enter the history when tapped. Only colors chosen through the native `ColorPicker` push into `recentColors`.
- Selecting a color that is already in `recentColors` moves it to the front rather than adding a duplicate.
- Mutations to `activeColor` go through the existing `DrawingViewModel` undo registration path so picking a color is undoable.

## UI

### Swatch button

- Location: `FloatingToolbar`, placed next to `BrushControls`, before the tools row (undo/redo/pen/eraser/…).
- Shape: ~28pt circle filled with `activeColor`, with a thin contrasting ring so it stays visible against both white and dark backgrounds.
- Tapping opens a SwiftUI popover.

### Popover content (top to bottom)

1. **Fixed presets** — 10 swatches in a grid:
   black, white, light gray, dark gray, red, orange, yellow, green, blue, purple.
   Tap = set `activeColor`, close popover. No history write.
2. **Recents** — horizontal row of up to 6 swatches. Hidden when `recentColors` is empty. Tap = set `activeColor`, move that entry to front, close popover.
3. **"Personalizar…" button** — opens the native SwiftUI `ColorPicker` (HSB wheel + alpha). When the user dismisses the picker, the chosen color becomes `activeColor` and is pushed onto `recentColors`.

All three zones operate on the same binding and go through the same `setActiveColor(_:)` entry point in the view model so history / undo behave consistently.

## Data Flow

```
User taps swatch in popover
        │
        ▼
DrawingViewModel.setActiveColor(_:)
        │
        ├─ updates canvas.activeColor  (registered with UndoManager)
        └─ (if from ColorPicker) prepends to canvas.recentColors, cap 6, dedupe
        │
        ▼
SwiftUI re-renders CanvasView with new activeColor binding
        │
        ▼
CanvasView.pkTool(for:) builds PKInkingTool(.pen, color: activeColor.uiColor, width: …)
        │
        ▼
PencilKit draws subsequent strokes in the chosen color
```

`CodableColor` needs a small helper to produce a `UIColor` (with the stroke-opacity multiplier already applied, replacing the hardcoded `UIColor.black.withAlphaComponent(strokeOpacity)` at `CanvasView.swift:51`).

New strokes created via `StrokeConverter` already copy color through `Stroke.init(color:)`, so once `PKInkingTool` is using `activeColor`, the resulting `Stroke` records will carry the right color automatically — no converter changes expected, but this should be verified during implementation.

## Testing

- Unit test that `Canvas` round-trips `activeColor` and `recentColors` through `Codable`.
- Unit test that `setActiveColor` from the picker path dedupes and caps `recentColors` at 6.
- Unit test that `setActiveColor` from a preset path does **not** touch `recentColors`.
- Manual verification on the iPad:
  - Pick a preset → next Pencil stroke is that color.
  - Open native picker, pick a custom color → stroke is that color, color appears in recents after reopening popover.
  - Close and reopen the document → `activeColor` and `recentColors` are restored.
  - Undo after a color change reverts to the previous color.

## Open Questions

None blocking. The sculpt-mode coloring follow-up is deferred by explicit agreement.
