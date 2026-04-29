# Export — Design

## Goal

Let the user export their work to outside apps and storage. Two artifact families are supported: a **PNG image** of the current view (2D canvas or 3D sculpt snapshot) and a **3D mesh** in OBJ or USDZ. Delivery is the iOS share sheet, so AirDrop, Messages, "Save to Files", and third-party apps are all reachable through one flow.

## Scope

**In scope**
- PNG export of the 2D `PKCanvasView` from the Drawing screen.
- PNG snapshot of the 3D `MTKView` (sculpt scene as currently rendered) from the Sculpt screen.
- OBJ and USDZ export of `SculptObject` meshes (geometry only) via `ModelIO`.
- Per-screen export entry point in the `FloatingToolbar` ("share" SF Symbol).
- A scope picker in Sculpt mode when the document has more than one `SculptObject`: "Active object" vs "Whole scene".
- Files written to `FileManager.default.temporaryDirectory`, handed to a SwiftUI `ShareLink(item: url)` (iOS 16+) which natively wraps `UIActivityViewController` and supports file URLs.

**Out of scope (explicit follow-ups)**
- Baking `SurfaceStroke`s into the exported mesh (vertex colors or extra geometry). The exported OBJ/USDZ in v1 is bare mesh; surface drawings are visible only in the PNG snapshot.
- JPEG output. PNG covers transparency and lossless quality; JPEG can be added if a real need emerges.
- A unified "Export" menu that adapts to the current mode. The agreed design is per-screen entry points.
- User-controlled resolution. Export uses native screen scale.
- Async export with progress UI. Operation is fast enough for v1; revisit if specific scenes prove too slow.

## Module Layout

New directory `PenSculpt/Export/`:

- `ExportFormat.swift` — small enums describing what's being exported.
- `ImageRenderer.swift` — produces a PNG file URL from a `PKCanvasView` or an `MTKView`.
- `MeshExporter.swift` — produces an OBJ or USDZ file URL from an array of `SculptObject` using `ModelIO`.
- `ExportError.swift` — typed errors propagated to the UI.

All four are stateless: `enum`s and free / `static` functions, mirroring how other utilities in the project are organized (`StrokeConverter`, `ContourExtractor`, `ShapeInflater`, etc.).

### `ExportFormat`

```swift
enum MeshFormat { case obj, usdz }
enum SculptScope { case activeOnly, all }
```

The view layer composes these as needed when calling the renderers and exporters; there is no single "ExportRequest" sum type — keeping the call sites explicit.

## Image Export

### 2D canvas (Drawing screen)

`ImageRenderer.renderPNG(from canvasView: PKCanvasView) throws -> URL`

1. Create a `UIGraphicsImageRenderer` with `canvasView.bounds` and `UIScreen.main.scale`.
2. Inside the render block:
   - If `canvasView.backgroundColor` is non-nil and not fully transparent, fill `bounds` with it. This respects a future canvas-background feature; today the canvas has no UI for this and the property is `.clear`, so the PNG comes out with alpha.
   - Draw `canvasView.drawing.image(from: bounds, scale: UIScreen.main.scale)` on top.
3. Convert the resulting `UIImage` to PNG data (`pngData()`).
4. Write to `temporaryDirectory/pensculpt-<timestamp>.png`. Return the URL.

Why not `canvasView.drawing.image()` alone: that helper ignores the view's background color. Going through `UIGraphicsImageRenderer` keeps the door open for a future "canvas background" feature without rewriting the export path.

### 3D snapshot (Sculpt screen)

`ImageRenderer.renderPNG(from metalView: MTKView) throws -> URL`

1. Create a `UIGraphicsImageRenderer` with `metalView.bounds` and `UIScreen.main.scale`.
2. Inside the render block, call `metalView.drawHierarchy(in: bounds, afterScreenUpdates: true)`. This API captures Metal layers correctly on iOS 13+.
3. PNG-encode and write to `temporaryDirectory`. Return the URL.

The renderer's `clearColor` (currently `(0.95, 0.95, 0.96, 1)`) is baked into the snapshot. Surface strokes are visible because they're already on screen at capture time.

If `drawHierarchy` produces poor quality on real hardware (banding, missed frames), the fallback is to render the same scene to an offscreen `MTLTexture` and convert via `CIImage`. Not implemented in v1.

## Mesh Export

`MeshExporter.export(_ objects: [SculptObject], format: MeshFormat) throws -> URL`

1. Pre-check: if `objects` is empty or every object's `mesh.isEmpty`, throw `ExportError.emptyContent`.
2. `let device = MTLCreateSystemDefaultDevice()` — required because `MTKMeshBufferAllocator` needs a device. If `nil`, throw `ExportError.modelIOFailed(...)`.
3. `let allocator = MTKMeshBufferAllocator(device: device)`.
4. Build an `MDLAsset(bufferAllocator: allocator)`.
5. For each `SculptObject`:
   - Build `MDLVertexDescriptor` with two attributes: position (`.float3`, `MDLVertexAttributePosition`) and normal (`.float3`, `MDLVertexAttributeNormal`), interleaved in a single buffer layout (stride = 24 bytes). This matches `MeshVertex`'s memory layout.
   - Pack `mesh.vertices` directly into a vertex buffer of size `vertices.count * MemoryLayout<MeshVertex>.stride`.
   - Pack `mesh.faces` into an index buffer of `UInt32`s (`faces.count * 3` indices).
   - Build `MDLSubmesh(indexBuffer:indexCount:indexType:.uint32, geometryType:.triangles, material:nil)`.
   - Build `MDLMesh(vertexBuffer:vertexCount:descriptor:submeshes:[submesh])`. Set its `name` to `"object-\(object.id.uuidString)"` so OBJ groups have a stable name.
   - Append to the asset.
6. `asset.export(to: tempURL)` where the URL extension is `.obj` or `.usdz`. ModelIO infers format from extension and writes the file.

Behavior per format:
- **OBJ** with multiple objects writes a single text file with `g <name>` markers. ModelIO may emit a sidecar `.mtl` next to the `.obj` referencing a default material; the share sheet only carries the URL we hand it (the `.obj`), so the `.mtl` is not shared. Receivers see geometry only, which is acceptable for v1 (no materials are authored).
- **USDZ** is a zip of `.usdc` plus assets, supports multiple meshes natively. One file, one share.

The caller (the SculptScreen UI) is responsible for filtering the array based on `SculptScope` before invoking `MeshExporter`. `MeshExporter` itself takes a plain `[SculptObject]`.

## UI

### DrawingScreen

Add a "share" button (`SF Symbol "square.and.arrow.up"`) to `FloatingToolbar`, placed near the existing tool row. Tap:

1. Call `ImageRenderer.renderPNG(from: canvasView)`.
2. On success, set `@State var shareURL: URL?`; the toolbar's `ShareLink(item: url)` is gated behind that state and the share sheet appears.
3. On failure, set `@State var exportError: ExportError?` and present an alert.

The active `PKCanvasView` reference must be reachable from `DrawingScreen`. Today `CanvasView` is a `UIViewRepresentable`; expose the underlying `PKCanvasView` to the parent via a `Coordinator` callback or a `@Binding<PKCanvasView?>` initialized once `makeUIView` runs. Implementation will pick whichever is least intrusive.

### SculptScreen

Add the same "share" button to `FloatingToolbar` (the project's shared toolbar; sculpt-mode-specific items are toggled via the existing `AppMode` flag). Tap opens a SwiftUI `confirmationDialog` with these choices:

1. **Image (PNG)** — calls `ImageRenderer.renderPNG(from: metalView)`.
2. **3D Mesh (OBJ)** — opens scope picker, then `MeshExporter.export(_, format: .obj)`.
3. **3D Mesh (USDZ)** — opens scope picker, then `MeshExporter.export(_, format: .usdz)`.

The scope picker is a second step shown only when `sculptObjects.count > 1`:
- **Active object** — `[activeObject].compactMap { $0 }`.
- **Whole scene** — `sculptObjects`.

If there's a single object, skip the scope picker and use it directly.

The chosen URL is then handed to a `ShareLink` / `UIActivityViewController`.

Concretely, the SculptScreen state machine becomes:

```
exportSheetState: .closed | .formatPicker | .scopePicker(MeshFormat) | .ready(URL)
```

Switching states drives which `.sheet` / `.confirmationDialog` is shown.

## Data Flow

```
User taps share in toolbar
        │
        ▼
View calls ImageRenderer or MeshExporter (sync, on main)
        │
        ├─ throws ExportError → alert
        └─ returns URL → ShareLink presents share sheet
```

No view-model layer added — these are one-shot file operations and don't carry state worth keeping in a view model. If async or progress is needed later, wrapping in a `Task { … }` is straightforward.

## Errors

```swift
enum ExportError: LocalizedError {
    case emptyContent           // canvas empty or no SculptObjects
    case renderFailed           // UIGraphicsImageRenderer / drawHierarchy failed
    case modelIOFailed(Error)   // ModelIO threw / device unavailable
    case writeFailed(Error)     // file write failed
}
```

Each case maps to a short `errorDescription` so a SwiftUI alert can show it. No retry logic; the user can re-tap.

`emptyContent` cases:
- Canvas has zero strokes **and** no background color → "Nothing to export".
- Sculpt mode and selected scope yields zero meshes (e.g. "Active object" but nothing is active) → "Nothing to export".

## Testing

Unit tests in `PenSculptTests/Export/`:

- `ImageRendererTests`
  - 2D path: build a `PKCanvasView` in a hosting controller, draw a synthetic stroke, render PNG, assert non-zero file size and that decoded `UIImage.size` matches `bounds.size * scale`.
  - Skip the 3D `MTKView` path in unit tests — it requires a live Metal context that's flaky under XCTest. Manual verification covers it.

- `MeshExporterTests`
  - Build a synthetic cube `SculptObject` (8 vertices, 12 triangles).
  - Export OBJ → parse the text, assert 8 lines starting with `v ` and 12 starting with `f `.
  - Export USDZ → assert file exists, has size > 0, magic bytes are `PK` (zip).

Manual verification on iPad:
- Drawing screen: draw, tap share, confirm "Save to Files" produces a valid PNG.
- Sculpt screen with one object: tap share → image, OBJ, USDZ all work; OBJ opens in a desktop viewer; USDZ opens in AR Quick Look.
- Sculpt screen with multiple objects: scope picker appears; "Active" exports just the highlighted one; "Whole scene" exports all.
- Empty canvas / empty sculpt scene: alert appears, no file written.

## Open Questions

None blocking. The surface-stroke baking and resolution controls are deferred by explicit agreement.
