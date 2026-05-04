# Pencil Hover Tooltips — Design

**Data:** 2026-05-04
**Status:** Aprovado (pendente review do usuário)
**Autor:** Alexandre + Claude

## Problema

Os botões de toolbar do PenSculpt são quase todos ícone-only (SF Symbols). Em uso real, a função de vários deles não é óbvia — o próprio usuário precisou perguntar pra que serviam (lasso, autosave, re-infer, deform, surface vs space, etc.). Falta um mecanismo de descoberta que não polua a interface.

## Solução

Tooltips contextuais que aparecem ao **aproximar a Apple Pencil Pro/2 de um botão** (hover) ou ao **segurar o dedo no botão** por meio segundo (long-press, fallback). Um botão de toggle global liga/desliga a feature.

## Decisões de produto

1. **Escopo:** botões ícone-only das toolbars principais (FloatingToolbar do DrawingScreen, nav bar do DrawingScreen, toolbar do SculptScreen). ~15 botões. Botões do popover de cor e do BrushControls ficam de fora nesta versão.
2. **Trigger duplo:** hover de Pencil (iOS 17.5+) e long-press de 0.5s. Mesma UI nos dois casos.
3. **Toggle global:** botão dedicado (ícone `questionmark.circle` / `questionmark.circle.fill`) presente nas duas telas. Estado persistido em `@AppStorage`. Default = ligado.
4. **Conteúdo:** título curto obrigatório (1-3 palavras) + descrição opcional (frase curta) por botão. Botões óbvios (undo, redo, lixeira, share) só recebem título; botões cuja função não é evidente recebem ambos.
5. **Timing:** hover precisa de 400ms estável antes de mostrar (evita flicker quando a Pencil só passa por cima). Some imediato ao sair. Long-press mostra após 500ms e some sozinho após ~2s.
6. **Posição:** auto — sistema decide acima/abaixo do botão conforme espaço disponível.

## Arquitetura

Três peças novas, todas em `PenSculpt/Views/Tooltips/`:

1. **`TooltipID`** — enum exaustivo de IDs (um por botão coberto). Cada caso resolve para `TooltipContent` (título + descrição opcional). Centraliza todas as strings num único arquivo, facilita auditoria de cobertura e futura localização.
2. **`.tooltip(_:)`** — ViewModifier aplicado em cada botão. Encapsula:
   - `onContinuousHover` para detectar Pencil próxima.
   - `onLongPressGesture` (sem consumir o tap normal) como fallback.
   - Lê `@AppStorage("tooltipsEnabled")` — se desligado, modifier vira no-op.
   - Mostra a tooltip via `.popover` com `presentationCompactAdaptation(.popover)` pra não virar sheet em iPad.
3. **`TooltipsToggleButton`** — botão pequeno que liga/desliga o `@AppStorage`. Adicionado no nav bar do DrawingScreen e na toolbar do SculptScreen.

Componente interno auxiliar: `TooltipView` (a caixinha visual).

## Cobertura de botões

| Tela | Botão | TooltipID | Descrição extra? |
|------|-------|-----------|------------------|
| DrawingScreen — FloatingToolbar | Color swatch | `colorSwatch` | Sim |
| DrawingScreen — FloatingToolbar | Undo / Redo | `undo`, `redo` | Não |
| DrawingScreen — FloatingToolbar | Tools (Pen/Pencil/Marker/Eraser) | `tool*` | Sim (cada um) |
| DrawingScreen — FloatingToolbar | Trash | `clear` | Sim |
| DrawingScreen — FloatingToolbar | Share | `exportImage` | Sim |
| DrawingScreen — bottom | Toggle toolbar (chevron/ellipsis) | `toolbarCollapse` | Sim |
| DrawingScreen — nav bar | Lasso/pencil mode toggle | `modeToggle` | Sim |
| DrawingScreen — nav bar | Autosave toggle | `autosaveToggle` | Sim |
| DrawingScreen — nav bar | Save | `save` | Não |
| DrawingScreen — nav bar | Tooltips toggle | `tooltipsToggle` | Sim |
| SculptScreen — toolbar | Close (X) | `sculptClose` | Não |
| SculptScreen — toolbar | Re-infer | `sculptReinfer` | Sim |
| SculptScreen — toolbar | Re-infer morph (sparkles) | `sculptReinferMorph` | Sim |
| SculptScreen — toolbar | Auto-project toggle | `sculptAutoProject` | Sim |
| SculptScreen — toolbar | Export | `sculptExport` | Sim |
| SculptScreen — toolbar | Color swatch | `sculptColorSwatch` | Sim |
| SculptScreen — toolbar | Surface vs space strokes | `sculptSurfaceSpace` | Sim |
| SculptScreen — toolbar | Rotate mode | `sculptRotate` | Sim |
| SculptScreen — toolbar | Eraser/smooth | `sculptEraser` | Sim |
| SculptScreen — toolbar | Deform mode | `sculptDeform` | Sim |
| SculptScreen — toolbar | Tooltips toggle | `tooltipsToggle` | (compartilhado) |

Os textos efetivos de cada caso são definidos no `TooltipID` e podem ser ajustados na revisão. Versão inicial será gerada pelo plano de implementação a partir do nome semântico de cada botão.

## Testes

Em `PenSculptTests/`:

- **`TooltipIDTests.swift`** (novo): cada caso de `TooltipID` retorna `TooltipContent` com título não-vazio. Cobertura via `CaseIterable`.
- **`TooltipModifierTests.swift`** (novo, se viável): com `tooltipsEnabled = false`, hover/long-press não mostram nada. Pode ser limitado dado que SwiftUI gestos são difíceis de driver em XCTest puro.

Verificação manual no iPad real (Pencil Pro):
- Hover sobre cada botão coberto → tooltip aparece após ~400ms, some ao sair.
- Long-press em qualquer botão → mesma tooltip, some sozinho.
- Tap normal nos botões continua funcionando (long-press não consome).
- Toggle off → nada acontece em hover nem long-press; botão de toggle continua respondendo.
- Estado do toggle persiste após relaunch.
- Tooltip não vaza fora da tela (auto-posicionamento).

## Fora de escopo

- Tooltips em controles secundários (BrushControls, ColorPickerPopover, dialogs de export).
- Localização (i18n) — strings em inglês hardcoded no enum. Estrutura permite migrar pra `String.LocalizationValue` depois sem refactor.
- Animação custom além de fade.
- Preferência de delay configurável pelo usuário.
- Atalhos de teclado nos textos.

## Risco / observações

- **Conflito de gesto:** se algum botão já tiver gesture handler que o long-press de tooltip atrapalhe (ex: Pencil double-tap em CanvasView), restringir o modifier a esses botões ou trocar long-press por `.contextMenu` como alternativa.
- **Hover só funciona em hardware real:** Pencil Pro ou Pencil 2ª geração + iPad com suporte a hover. Simulator não simula hover; testes desse caminho são manuais.
- **Performance:** modifier é leve (sem timers ativos quando não há hover). Aplicar em ~15 botões não tem custo perceptível.
- **Posicionamento:** `.popover` em iPad é estável; se o auto-posicionamento do SwiftUI ficar visualmente ruim em algum botão (ex: tooltip cobrindo o próprio botão), substituir por `.overlay` posicionado manualmente nesse caso específico.
