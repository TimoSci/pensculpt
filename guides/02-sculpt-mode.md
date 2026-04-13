# Sculpt Mode

This guide covers the 3D sculpt features in PenSculpt. To enter Sculpt mode, first select strokes using the lasso in Draw mode, then tap the "Sculpt" button.

## Screen Layout

When you enter Sculpt mode, your selected strokes are inflated into a 3D object. The interface has:

- **Top left** — close button (X), re-infer button, morph re-infer (beta), and auto-project toggle
- **Top center** — object counter (e.g., "1 / 3") when multiple objects exist
- **Bottom center** — brush size and opacity controls
- **Bottom left** — rotate button (circle with 3D axes)
- **Bottom right** — eraser button and deform button (hand icon)

## Rotating the Object

Two ways to rotate:
- **Two-finger drag** anywhere on the screen
- **Hold the rotate button** (bottom left) and drag with the pencil

The rotate button glows blue while active.

## Drawing on the Surface

Simply touch the Apple Pencil to the 3D surface to draw. No mode switch needed — the app distinguishes between finger rotation and pencil drawing automatically.

## Deform Mode

Tap the **hand icon** (bottom right) to enter Deform mode. It glows orange when active.

- **Drag on the surface** to push/pull the mesh
- **Pen pressure** controls the brush radius (harder press = wider area)
- The deformation follows a smooth Gaussian falloff from the center
- An orange dashed circle shows your brush area

Tap the hand icon again to return to Draw mode.

## Eraser

Tap the **eraser button** (bottom right, next to the hand):
- **In Draw mode**: erases surface strokes you've drawn on the 3D object
- **In Deform mode**: activates smooth mode (smooths out mesh deformations)

The eraser glows mint when active.

## Apple Pencil Double-Tap

- **In Draw mode**: toggles erase stroke on/off
- **In Deform mode**: toggles smooth mode on/off

## Re-Inference

If you go back to the drawing canvas, add or modify strokes, and return to Sculpt mode, the 3D shape updates automatically.

You can also manually re-infer:
- **Re-infer button** (circular arrow, top left) — regenerates the mesh, preserving surface strokes
- **Morph re-infer** (sparkles icon, beta) — smoothly morphs from old mesh to new mesh

## Auto-Project Toggle

The **arrow-down document icon** (top left) controls whether surface strokes drawn in 3D are projected back onto the 2D canvas when you close Sculpt mode. Blue when enabled.

## Multiple Objects

If your document has multiple sculpt objects:
- The counter at the top shows which object is active (e.g., "1 / 3")
- **Tap** the 3D view to cycle between objects
- Only the active object responds to drawing and deformation
- Non-active objects appear dimmed

## Tips

- Rotate frequently while drawing to build up the 3D surface from multiple angles
- Use deform mode to refine the shape after drawing
- The smooth eraser in deform mode is great for fixing rough areas
- Surface strokes survive re-inference — they get reprojected onto the new mesh
