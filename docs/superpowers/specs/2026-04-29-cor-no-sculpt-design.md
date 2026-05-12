# Cor no Sculpt — Design

**Data:** 2026-04-29
**Status:** Aprovado (pendente review do usuário)
**Autor:** Alexandre + Claude

## Problema

Surface strokes desenhados no SculptScreen são sempre azuis (`(0.2, 0.2, 0.8)` hardcoded em 2 lugares no `SculptRenderer` e em `SurfaceStroke.projectTo2D()`). O usuário precisa de cor variada no 3D para trabalhos complexos. O `ColorPickerPopover` e o `Canvas.activeColor` já existem para o canvas 2D — falta integrar no fluxo do sculpt.

## Decisões de produto

1. **Fonte da cor ativa:** compartilhada com DrawingScreen. `Canvas.activeColor` é a única fonte de verdade. Mudar a cor no SculptScreen muda no 2D e vice-versa. Mesma `recentColors`. Mesmo undo.
2. **Granularidade:** por stroke. Cada `SurfaceStroke` armazena sua própria cor (espelha o modelo 2D, permite multi-cor por objeto).
3. **UI:** swatch circular igual ao do 2D, no toolbar inferior do SculptScreen, antes do `BrushControls`. Reutiliza o `ColorPickerPopover` existente.

## Mudanças

### 1. Modelo

`PenSculpt/Models/SculptObject.swift` — adicionar `color` em `SurfaceStroke`:

```swift
struct SurfaceStroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var points: [SIMD3<Float>]
    var widths: [Float]
    var opacity: Float
    var color: CodableColor

    init(id: UUID = UUID(), points: [SIMD3<Float>] = [],
         widths: [Float] = [], opacity: Float = 1,
         color: CodableColor = .black) {
        ...
    }

    init(from decoder: Decoder) throws {
        ...
        color = try container.decodeIfPresent(CodableColor.self, forKey: .color)
            ?? CodableColor(red: 0.2, green: 0.2, blue: 0.8, alpha: 1)
    }
}
```

- Init default = `.black` (previsível para chamadas em código novo).
- Decode fallback = azul histórico `(0.2, 0.2, 0.8)`, garantindo retrocompat visual para documentos `.pensculpt` salvos antes desta mudança.

### 2. Propagação da cor ativa

**`PenSculpt/Models/Stroke.swift`** — adicionar helper:

```swift
extension CodableColor {
    func simd4(opacity: Float = 1) -> SIMD4<Float> {
        SIMD4(Float(red), Float(green), Float(blue), Float(alpha) * opacity)
    }
}
```

**`PenSculpt/Views/DrawingScreen.swift`** — passar pro `SculptScreen` (linha 34):

```swift
.fullScreenCover(isPresented: $vm.showSculptScreen, onDismiss: projectSurfaceStrokes) {
    SculptScreen(
        ...,
        activeColor: vm.canvas.activeColor,
        recentColors: vm.canvas.recentColors,
        onSelectPresetColor: { setActiveColorWithUndo($0, addToRecents: false) },
        onSelectCustomColor: { setActiveColorWithUndo($0, addToRecents: true) }
    )
}
```

**`PenSculpt/Views/SculptScreen.swift`** — receber e passar adiante:

```swift
struct SculptScreen: View {
    ...
    var activeColor: CodableColor
    var recentColors: [CodableColor]
    var onSelectPresetColor: (CodableColor) -> Void
    var onSelectCustomColor: (CodableColor) -> Void
    @State private var showColorPopover = false
```

E passar `activeColor` pro `MetalCanvasView`:

```swift
MetalCanvasView(
    ...,
    activeColor: activeColor
)
```

**`PenSculpt/Rendering/MetalCanvasView.swift`** — receber `activeColor`, propagar pro renderer e usar no momento de criar o stroke:

```swift
struct MetalCanvasView: UIViewRepresentable {
    ...
    var activeColor: CodableColor = .black
    ...

    func updateUIView(...) {
        ...
        context.coordinator.renderer?.currentStrokeColor = activeColor
        context.coordinator.activeColor = activeColor
    }
}

class Coordinator: ... {
    var activeColor: CodableColor = .black
    ...
    // ao criar SurfaceStroke (linha ~315):
    let stroke = SurfaceStroke(
        points: renderer.currentStrokePoints,
        widths: renderer.currentStrokeWidths,
        opacity: renderer.brushOpacity,
        color: activeColor
    )
}
```

### 3. Renderização

**`PenSculpt/Rendering/SculptRenderer.swift`** — adicionar `currentStrokeColor` e usar `stroke.color` nos draws:

```swift
class SculptRenderer: ... {
    ...
    var currentStrokeColor: CodableColor = .black
    ...
}

private func drawSurfaceStrokes(...) {
    ...
    for obj in sculptObjects where obj.id == activeObjectID {
        for stroke in obj.surfaceStrokes {
            ...
            let color = stroke.color.simd4(opacity: stroke.opacity)  // antes: hardcoded
            drawStrokeStrip(...)
        }
    }

    if currentStrokePoints.count > 1 {
        ...
        drawStrokeStrip(currentStrokePoints, widths: widths,
                        color: currentStrokeColor.simd4(opacity: brushOpacity * 0.6),  // antes: hardcoded
                        encoder: encoder)
    }
}
```

Shader e pipelines não mudam — já aceitam cor por vértice via buffer `colors[]`.

### 4. UI — swatch no SculptScreen

`PenSculpt/Views/SculptScreen.swift`, dentro do `.overlay(alignment: .bottom)` (linha ~129), antes de `BrushControls`:

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

    BrushControls(...)
    ...
}
```

### 5. Projeção 2D

**`PenSculpt/Models/SculptObject.swift`** — `projectTo2D()` (linha 30) usa a cor do stroke:

```swift
func projectTo2D() -> Stroke {
    ...
    let projColor = CodableColor(red: color.red, green: color.green,
                                 blue: color.blue, alpha: color.alpha * CGFloat(opacity))
    return Stroke(points: strokePoints, color: projColor)
}
```

### 6. Re-projeção em re-infer

**`PenSculpt/Models/SculptObject.swift`** — `reprojected(onto:)` (linha 46) propaga a cor:

```swift
return SurfaceStroke(id: id, points: newPoints, widths: newWidths,
                     opacity: opacity, color: color)
```

## Testes

Adicionar/atualizar em `PenSculptTests/`:

- **`SculptObjectTests.swift`** (ou novo arquivo):
  - `SurfaceStroke` Codable round-trip preserva `color`
  - Decode de payload sem campo `color` cai no azul default `(0.2, 0.2, 0.8)`
  - `projectTo2D()` retorna `Stroke` com a cor do `SurfaceStroke`
  - `reprojected(onto:)` preserva `color` ao reconstruir o stroke

Testes de UI/Metal não automatizados — verificação manual:

- Desenhar surface stroke com cor X → ver renderizado em X
- Mudar cor no swatch do SculptScreen → cor mudou no DrawingScreen
- Re-infer mantém cor dos strokes
- Sair do SculptScreen e voltar → cor persistida no documento
- Abrir doc antigo `.pensculpt` → strokes 3D antigos seguem azuis

## Fora de escopo

- Cor por vértice no mesh (mesh segue cinza neutro)
- Sculpt screen importar cor dos strokes 2D originais ao inferir o objeto
- Color picker independente no SculptScreen
- Mudanças no shader Metal (já suporta cor por vértice)

## Risco / observações

- O `SurfaceStroke` recém-criado é appended em duas listas (na cópia do renderer e via callback `onSurfaceStrokeCompleted` no binding de `SculptScreen`). É a mesma instância — basta criar uma vez com a cor correta.
- O preview do stroke em progresso usa `currentStrokeColor` que precisa ser setado a cada `updateUIView`, não só em `makeUIView`, pra refletir mudanças de cor sem precisar começar um novo stroke.
- `projectTo2D()` hoje monta a cor com `alpha: CGFloat(opacity)`. Após a mudança vira `alpha: color.alpha * CGFloat(opacity)` — comportamento idêntico para strokes que tenham `color.alpha == 1` (todos os criados pela UI), e correto para casos com alpha custom no futuro.
