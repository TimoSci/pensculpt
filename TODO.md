# PenSculpt TODO

Status legend:
- `[ ]` Not started
- `[x]` Completed
- Optimization: `O[ ]` Not optimized / `O[x]` Code optimized
- Simplification: `S[ ]` Not simplified / `S[x]` Code simplified

---

## Stage 1: Drawing Engine

- [x] Project setup (Xcode project, targets, UTI) — O[ ] S[ ]
- [x] StrokePoint model (position, pressure, tilt, azimuth, timestamp) — O[ ] S[ ]
- [x] Stroke model (points, color, bounding box, Codable) — O[ ] S[ ]
- [x] Canvas model (stroke management, Codable) — O[ ] S[ ]
- [x] StrokeConverter (PKStroke to internal Stroke) — O[ ] S[ ]
- [x] CanvasView (PKCanvasView UIViewRepresentable wrapper) — O[ ] S[ ]
- [x] FloatingToolbar (undo, redo, eraser, clear) — O[ ] S[x]
- [x] DrawingScreen (full-screen canvas with toolbar button) — O[ ] S[x]
- [x] PenSculptDocument (ReferenceFileDocument, .pensculpt package format) — O[ ] S[ ]
- [x] App entry point (DocumentGroup wiring) — O[ ] S[ ]
- [x] Undo/Redo (UndoManager registration for add/remove/clear) — O[ ] S[ ]
- [x] Unit tests (StrokePoint, Stroke, Canvas, StrokeConverter, Document) — O[ ] S[ ]
- [x] Drawing basics guide — O[ ] S[ ]
- [x] Apple Pencil double-tap toggle (pen/eraser) — O[ ] S[ ]
- [x] Apple Pencil hover cursor preview (provided by PencilKit) — O[x] S[x]

## Stage 2: Sculpt Mode

### Selection System
- [ ] SelectionStrategy protocol — O[ ] S[ ]
- [ ] StrokeGroup model — O[ ] S[ ]
- [ ] LassoSelection (point-in-polygon, 50% threshold) — O[ ] S[ ]
- [ ] Selection UI (mode toggle, lasso overlay, highlights) — O[ ] S[ ]

### Inference Pipeline
- [ ] ContourAnalyzer (silhouette extraction from strokes) — O[ ] S[ ]
- [ ] SkeletonExtractor (distance transform, Zhang-Suen thinning) — O[ ] S[ ]
- [ ] Segmenter (branch points, curvature threshold) — O[ ] S[ ]
- [ ] PrimitiveFitter (circularity, aspect ratio, taper classification) — O[ ] S[ ]
- [ ] MeshAssembler (implicit surface blending, Marching Cubes) — O[ ] S[ ]
- [ ] StrokeMapper (orthographic projection, UV mapping, seam splitting) — O[ ] S[ ]
- [ ] SculptObject model — O[ ] S[ ]
- [ ] InferencePipeline coordinator (async, fallback on failure) — O[ ] S[ ]

### Metal Renderer
- [ ] MetalCanvasView (MTKView, orthographic camera) — O[ ] S[ ]
- [ ] Mesh rendering (diffuse lighting, sketch aesthetic) — O[ ] S[ ]
- [ ] Stroke rendering (triangle strips, pressure-based width) — O[ ] S[ ]
- [ ] Stroke style toggle (screen-space vs surface-space) — O[ ] S[ ]
- [ ] Metal shaders (vertex + fragment) — O[ ] S[ ]

### Sculpt Interaction
- [ ] Rotation (two-finger drag, arcball) — O[ ] S[ ]
- [ ] Draw-on-surface (ray cast, bake at viewing angle) — O[ ] S[ ]
- [ ] Thumb button for pen-rotate mode — O[ ] S[ ]
- [ ] Mesh deformation (soft brush, Gaussian falloff) — O[ ] S[ ]
- [ ] Re-inference (async, correction preservation, cross-fade) — O[ ] S[ ]

### Integration
- [ ] SculptScreen view — O[ ] S[ ]
- [ ] Mode switching (Draw → Select → Sculpt) — O[ ] S[ ]
- [ ] Multi-object interaction (active/dimmed) — O[ ] S[ ]
- [ ] Document persistence for SculptObjects — O[ ] S[ ]
- [ ] Sculpt mode guide — O[ ] S[ ]

## Future Stages
- [ ] Color picker and color strokes — O[ ] S[ ]
- [ ] Grow selection (tap + hold duration) — O[ ] S[ ]
- [ ] Export (image, OBJ/USDZ, share sheet) — O[ ] S[ ]
- [ ] Perspective camera toggle — O[ ] S[ ]
