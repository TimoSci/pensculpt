# PenSculpt Design Spec

## Overview

PenSculpt is an iPad drawing app built for Apple Pencil that lets users create 2D drawings and then "sculpt" them into pseudo-3D objects. The app infers 3D shape from 2D strokes, maps the strokes onto the inferred geometry, and allows the user to rotate, correct, and refine the result — all with the pen as the primary interface.

**Design philosophy:** Creative/artistic tool. Minimal UI, maximum canvas. The pen is the primary interface.

## Architecture

**Tech stack:**
- **SwiftUI** for the app shell (toolbar, settings, document management)
- **PencilKit** for Stage 1 drawing (pressure, tilt, palm rejection, low-latency rendering)
- **Custom Metal renderer** for Stage 2 3D rendering (pixel-level control over stroke-on-surface rendering)
- **UIKit** bridging where needed (PKCanvasView via UIViewRepresentable, MTKView subclass)

**Two primary modes:**
- **Draw Mode** (Stage 1): Full-screen PencilKit canvas, black and white, pen draws freely
- **Sculpt Mode** (Stage 2): Metal-rendered 3D view, rotate with fingers, draw corrections with pen

## Data Model

### Core Types

- **`Stroke`**: Converted from PencilKit's `PKStroke`. Contains per-point position, pressure, tilt, azimuth, timestamp, and color (defaults to black in Stage 1, ready for future color support).

- **`StrokeGroup`**: A collection of strokes selected together via lasso. Represents a logical unit the user wants to treat as one 3D object.

- **`SculptObject`**: A StrokeGroup + its inferred 3D decomposition (skeleton, fitted primitives, composite mesh) + user corrections at various angles + mesh distortions.

- **`Canvas`** (document root): Contains canvas dimensions, free (ungrouped) strokes, a list of SculptObjects, and app settings snapshot.

## Stage 1: Drawing Engine

### PencilKit Integration

A `PKCanvasView` wrapped in `UIViewRepresentable` for SwiftUI hosting. Black ink on white background only.

### Stroke Capture Pipeline

1. User draws with Apple Pencil — PencilKit handles all input processing
2. On stroke completion, `PKStroke` is converted to internal `Stroke` model (per-point position, pressure, tilt, azimuth, timestamp)
3. Internal `Stroke` is appended to `Canvas` and becomes the canonical representation

**Why the conversion:** PencilKit's internal stroke format is opaque. Stage 2 needs full access to stroke geometry for 3D mapping and Metal rendering. Conversion happens once per stroke, transparent to the user.

### Minimal UI

- Full-screen canvas, no visible chrome by default
- Small floating toolbar (triggered by swipe from screen edge — avoids conflict with iPadOS three-finger copy/paste/undo gestures): undo, redo, clear, eraser toggle
- Apple Pencil double-tap: toggles between draw and eraser tools (standard Pencil 2 / Pencil Pro behavior)
- Apple Pencil hover: shows a cursor preview dot at the hover point (Pencil Pro / M-series iPad support)
- Eraser: PencilKit's built-in eraser (stroke or pixel level)
- No color picker in Stage 1 — black on white only
- Toolbar built as extensible component for future tools/pickers (zero refactoring to add color later)

### Extensibility Hooks

- `Stroke.color` property exists from Stage 1, defaulting to black
- Toolbar architecture supports adding new tools/pickers without refactoring

## Stage 2: Lasso Selection & Stroke Grouping

### Selection Mode

A mode toggle on the floating toolbar switches from Draw to Select. In Select mode, pen input creates a lasso path instead of a stroke.

### Lasso Mechanics

1. User draws a loop around target strokes. When the pen lifts, a straight line segment connects the last point to the first point, closing the lasso regardless of distance.
2. Strokes with 50% or more of their sample points inside the lasso polygon are included in the selection. This threshold may be tuned during testing.
3. Selected strokes highlight (subtle glow or color shift)
4. User confirms selection (tap "Sculpt" button or gesture) — creates `StrokeGroup` → `SculptObject`

### Selection Architecture

- `SelectionStrategy` protocol: given a point/gesture and current strokes, returns which strokes are selected
- `LassoSelectionStrategy`: Stage 2 implementation
- Future "grow selection" (tap + hold duration expands selection to surrounding features) becomes another `SelectionStrategy` conformance — plugs in without changing the selection flow

### Deselection

Tap on empty canvas to deselect. Tap on a different area to start a new selection.

### Multi-Object Interaction

The canvas can contain multiple SculptObjects. In Sculpt mode, one object is "active" at a time — determined by which object the user last interacted with (tapped, rotated, or drew on). Non-active SculptObjects are visible but dimmed. The user taps a different object to make it active. Rotation and drawing only affect the active object. All objects share the same 3D scene and coordinate space.

## Stage 2: 3D Shape Inference Engine

### Decomposition Pipeline

When a `StrokeGroup` is promoted to a `SculptObject`:

1. **Contour analysis:** Extract outer boundary/silhouette of combined strokes. Identify closed regions and branching structures.

2. **Skeleton extraction:** Rasterize the silhouette to a bitmap (resolution: 512x512 normalized to the stroke group's bounding box, maintaining aspect ratio with padding), compute a distance transform, then apply Zhang-Suen thinning to extract the medial axis. This produces the structural "bones" — a stick figure through the center of each region. The bitmap approach is robust to the noise and gaps typical of hand-drawn input (vs. Voronoi-based methods that require clean vector input).

3. **Segmentation:** Break skeleton into segments at branch points and high-curvature joints (curvature threshold: configurable, starting at 45 degrees). Each segment = one "part" of the drawing.

4. **Primitive fitting:** For each segment, sample the silhouette cross-section perpendicular to the skeleton at regular intervals. Classify each cross-section by:
   - **Circularity** (`4 * pi * area / perimeter^2`, yields 1.0 for a perfect circle): > 0.7 → cylinder or sphere
   - **Aspect ratio** of bounding box: > 2.0 with low circularity → box
   - **Taper ratio** (width change along segment): > 1.5 → cone or truncated cone
   - **Fallback:** If no classification scores above threshold, or the segment is very thin (width < 5% of total silhouette extent), treat as an extruded plane (flat ribbon). "Flat" means the cross-section has insufficient area to meaningfully inflate into a volume.

   Ambiguous cases (multiple classifiers within 10% of each other) default to ellipsoid as the most forgiving general shape.

5. **Assembly:** Join fitted primitives at connection points using implicit surface blending (metaball-style field function). Each primitive defines a scalar field; the composite surface is the iso-surface of the summed fields. This produces smooth organic joints without explicit mesh stitching, which is important for complex shapes like animals. Mesh extracted via Marching Cubes at a configurable resolution (default: 64^3 grid).

6. **Stroke mapping:** Each original stroke is projected onto the composite mesh via orthographic projection from the original 2D viewing angle (the angle at which the strokes were drawn). For each stroke sample point, a ray is cast perpendicular to the view plane; the nearest front-face mesh intersection determines the 3D position and UV coordinate. Strokes that span seams between primitives are split at the seam boundary and mapped to each surface independently. Back-face ambiguity is resolved by always mapping to the front face from the current drawing angle.

### Handling Complex Shapes

The decomposition handles complex drawings (e.g., animals) by breaking them into multiple connected primitives — not by recognizing what the subject is, but by structural analysis of the silhouette. An animal becomes cylinders (legs), ellipsoid (body), sphere (head), connected at inferred joints.

### User Override

After inference, the user can:
- Rotate to inspect the result
- Draw new strokes at any angle (baked onto the surface at that viewing angle)
- Distort inferred geometry using soft-brush deformation: the pen contact point is the deformation center, pen pressure controls the brush radius of influence (larger pressure = wider area), and dragging in screen space is projected onto the local surface normal to push (drag away from surface) or pull (drag toward surface). The influence falls off with a smooth Gaussian curve from center to edge of the brush radius.

### Confidence and Refinement

The system stores user corrections in two forms:
- **Drawn strokes:** Stored with their world-space 3D positions (computed at the time of drawing from the viewing angle). On re-inference, these are re-projected onto the new mesh surface, so they survive topology changes.
- **Mesh distortions:** Stored as world-space displacement vectors at anchor points. On re-inference, each anchor point is matched to the nearest surface point on the new mesh and the displacement is re-applied. If the new mesh differs substantially in that region, the distortion may not transfer perfectly — the user can refine further.

If inference fails entirely (e.g., strokes are too sparse to extract a meaningful silhouette, or the skeleton is degenerate), the system falls back to presenting the strokes as a flat extruded plane and displays a brief notification: "Could not infer 3D shape — showing flat projection. Add more detail and try again."

## Stage 2: Fluid Rotate-and-Draw Workflow

The transition between rotating and drawing must be frictionless:

- **Rotate:** Two-finger drag rotates the object. Pen can also rotate via an on-screen thumb button held by the non-drawing hand.
- **Draw:** Pen touches the surface → immediately draws. No mode switch needed. System distinguishes rotate from draw by input type (finger vs. pen) or thumb modifier state.
- **Re-infer:** Quick double-tap on the object re-runs inference incorporating new strokes while preserving corrections. Optional auto-re-infer after each stroke with debounce (toggle in settings for manual vs. auto). Inference always runs asynchronously on a background thread — the renderer continues displaying the previous mesh until the new one is ready, then cross-fades to the updated geometry.

**Workflow:** Rotate a bit with fingers → draw a correction with the pen → rotate more → draw more. No toolbar trips, no mode toggles.

## Stage 2: Custom Metal 3D Renderer

### Why Custom Metal

PencilKit strokes have specific aesthetic qualities (pressure variation, smooth tapering) that must be faithfully reproduced on curved 3D surfaces. A custom renderer gives pixel-level control over how strokes deform, foreshorten, and maintain their character.

### Renderer Architecture

- **`MetalCanvasView`**: An `MTKView` subclass handling both 3D scene and 2D overlay for drawing corrections. Uses an **orthographic camera** by default to match the flat drawing aesthetic (the 2D strokes should look the same when entering Sculpt mode). Perspective projection available as a future toggle.

- **Render pipeline stages:**
  1. Mesh rendering — composite primitive mesh with basic diffuse lighting (no textures, sketch aesthetic)
  2. Stroke rendering — strokes as triangle strips on mesh surface, per-vertex width from pressure data. Custom vertex shader handles foreshortening.
  3. UI overlay — selection highlights, lasso path, rotation gizmo hints

### Stroke Style Toggle

Two modes, switchable via simple uniform in shader (no pipeline rebuild):

- **Screen-space mode:** Constant-width strokes regardless of surface orientation (comic/illustration style)
- **Surface-space mode:** Stroke width modulated by dot product of surface normal and view direction — strokes thin at grazing angles (realistic style)

### Performance

Target: 120fps on modern iPads (ProMotion). Mesh complexity from primitive decomposition is low (hundreds to low thousands of triangles per object). Stroke rendering is the bottleneck with many strokes — handled via instanced rendering and stroke LOD (simplify distant/small strokes).

## Document Model & Persistence

### Document Structure

`PenSculptDocument` — root type, conforming to `Codable`, working with SwiftUI's `ReferenceFileDocument`. (Chosen over `FileDocument` because `ReferenceFileDocument` pairs naturally with `UndoManager` for incremental undo/redo and supports incremental saves for the package format — avoiding full-snapshot serialization of potentially large mesh data on every change.)

### File Format

Custom `.pensculpt` package (UTI-based):
- `strokes.json` — canonical stroke data
- `sculpt_objects/` — one directory per SculptObject, each containing: `manifest.json` (metadata, primitive decomposition, correction anchors), `mesh.bin` (binary vertex/index buffers — compact and fast to load), `stroke_mappings.json` (UV coordinates linking strokes to mesh surfaces)
- `thumbnail.png` — file browser preview
- `metadata.json` — version, creation date, canvas size

### Undo/Redo

Built on `UndoManager`. Each action (stroke added, erased, group created, mesh distorted, correction drawn) is a discrete undoable operation. Works seamlessly across Draw and Sculpt modes.

### Autosave

Leverages SwiftUI document infrastructure for automatic save on changes with short debounce.

## Project Structure

```
PenSculpt/
├── App/                    # App entry point, document scene
├── Models/                 # Stroke, StrokeGroup, SculptObject, Canvas
├── Views/                  # SwiftUI views, toolbar, mode switcher
├── Drawing/                # PencilKit integration, stroke conversion
├── Selection/              # SelectionStrategy protocol, LassoSelection
├── Inference/              # Contour analysis, skeleton, primitive fitting, assembly
├── Renderer/               # Metal renderer, shaders, stroke rendering
├── Persistence/            # Document model, file format, codable conformances
├── Resources/              # Metal shader files, assets
└── Tests/                  # Unit tests per module
```

## Development Stages

### Stage 1 Deliverable
Working iPad app: draw with Apple Pencil in black and white, undo/redo, eraser, save/load. Internal stroke model with color and extensibility hooks in place but not exposed in UI.

### Stage 2 Deliverable
Lasso selection, 3D inference pipeline, Metal renderer, rotate-and-draw workflow, stroke style toggle (screen-space vs. surface-space), mesh distortion, correction baking. The full sculpt loop.

### Out of Scope for Stages 1-2
- **Export** (image, OBJ/USDZ, share sheet) — planned for a future stage
- **Collaboration / multi-user** — not planned

### Future Stage Hooks
- **Color:** `Stroke.color` property exists, needs picker UI
- **Grow selection:** `SelectionStrategy` protocol ready for new conformances
- **Additional tools:** Toolbar extensible by design
- **Export:** Document format designed to be convertible to standard 3D formats
