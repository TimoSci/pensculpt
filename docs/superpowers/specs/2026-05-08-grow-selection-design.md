# Grow Selection — Design

**Data:** 2026-05-08
**Status:** Aprovado (pendente review do usuário)
**Autor:** Alexandre + Claude

## Problema

Hoje a única forma de selecionar strokes no `DrawingScreen` é o **laço** (lasso): o usuário precisa desenhar um contorno em volta do que quer selecionar. Isso é preciso, mas trabalhoso quando:

- O alvo é "esse stroke e tudo que está visualmente conectado a ele" (ex: selecionar a janela inteira de um desenho de casa).
- O alvo tem geometria complexa onde traçar um contorno fechado é tedioso.
- O usuário quer iterar rapidamente entre seleções pequenas.

Falta um modo de seleção que opere por **proximidade/contiguidade**, não por região desenhada.

## Solução

**Grow selection**: o usuário faz um **tap+hold** com a Pencil; uma seleção começa do ponto/stroke tocado e cresce no tempo, incorporando strokes vizinhos. Solta = confirma.

Crescimento é por **raio expansivo no tempo**, com **velocidade adaptativa**: o algoritmo desacelera ao detectar zonas densas, criando "pausas naturais" que dão ao usuário a chance de soltar exatamente entre grupos (ex: entre a janela e a parede).

## Decisões de produto

(Validadas em sessão de brainstorming visual com o usuário em 2026-05-08.)

### 1. Origem dual

O comportamento varia pelo alvo do tap+hold:

- **Tap em cima de um stroke** → aquele stroke é a "semente". O crescimento começa a partir dele e se espalha pra strokes vizinhos.
- **Tap em área vazia do canvas** → uma "esfera de crescimento" virtual nasce naquele ponto. O raio começa pequeno e expande, capturando strokes que ela alcança.

Mesmo gesto, comportamento auto-selecionado pelo hit-test no início do hold.

### 2. Vizinhança por distância ponto-a-ponto com raio crescente

Para cada candidato, mede a **menor distância euclidiana** entre qualquer sample do stroke e a fronteira atual da seleção (origem-ponto, ou qualquer sample dos strokes já incluídos). Se essa distância está dentro do **raio efetivo atual**, o stroke entra.

O raio efetivo cresce com o tempo de hold (ver item 3). Strokes quase-encostando entram cedo; strokes mais isolados entram só se o raio crescer o suficiente.

### 3. Velocidade adaptativa por densidade

O raio cresce a uma velocidade base (~50 px/s na largura padrão de canvas), mas é **modulado por um fator de densidade**:

- Quando o próximo stroke a entrar está perto da fronteira atual (incremento pequeno de raio), velocidade fica próxima da base.
- Quando há um "gap" — próximo stroke exigiria um salto grande de raio — velocidade desacelera (até ~10% da base) por uma fração de segundo, criando uma **pausa**.
- Após a pausa, retoma velocidade base.

Resultado: em desenhos com clusters bem definidos (janela vs parede da casa), o crescimento "respira" entre grupos, dando ao usuário a chance de soltar no momento certo.

### 4. Visualização rica

Durante o hold:

- **Strokes incluídos:** highlight azul cheio (mesmo do laço atual — `SelectionHighlight`).
- **Esfera de crescimento:** círculo translúcido azul centrado na origem, com fronteira pontilhada, expandindo conforme o raio aumenta. Visível mesmo quando origem é um stroke (centrada no ponto inicial do tap).
- **Stroke candidato:** o próximo stroke que entrará pulsa em azul fraco (~1.2s/ciclo), antecipando inclusão.
- **Halo de pausa:** quando o algoritmo está em pausa adaptativa, um halo dourado aparece ao redor da esfera. Sinaliza "agora é momento bom de soltar".

Tudo desaparece ao soltar — só permanece o highlight azul nos strokes finalmente selecionados.

### 5. Cancelamento via Undo

Soltar a Pencil **sempre confirma** a seleção atual. Não há gesto de cancelamento durante o hold. Se o usuário não quiser a seleção resultante, usa **Undo** (Cmd+Z em hardware keyboard ou botão Undo da toolbar) pra revertê-la, igual ao laço.

Mantém consistência com o modelo mental do laço e simplifica a feature.

### 6. Coexistência por gesto

`AppMode .select` continua sendo o modo de seleção único. Dentro dele, o reconhecedor de gestos diferencia:

- **Drag** (movimento contínuo desde o toque) → laço (fluxo atual).
- **Tap+hold parado** (sem movimento por ~150ms) → grow selection.

Sem UI extra. Discoverability é coberta atualizando o tooltip do `modeToggle` (sistema de tooltips já existente) para incluir ambos os gestos — algo como **título:** "Select" / **descrição:** "Drag to lasso · Hold to grow selection". Atualização pontual no `TooltipID` enum.

**Plano B documentado:** se feedback de uso real mostrar que grow é difícil de descobrir ou que os gestos conflitam, evolui para um toggle dentro do modo Select (botão Lasso ↔ botão Grow lado a lado, no mesmo lugar onde o modo Select é configurado — não no toolbar principal).

## Arquitetura

Quatro peças novas em `PenSculpt/Drawing/Selection/`, mais um refator do `LassoSelection` existente.

### `SelectionStrategy` (protocol — novo)

Protocolo central que normaliza a interface entre as estratégias de seleção e o `DrawingViewModel`:

```swift
protocol SelectionStrategy {
    associatedtype Input
    static func select(input: Input, in canvas: Canvas) -> Set<UUID>
}
```

Cada estratégia define seu próprio `Input` (pontos do laço, semente do grow, etc.). O resultado é sempre um `Set<UUID>` de stroke IDs.

### `LassoStrategy` (refator de `LassoSelection`)

Refatora a lógica atual de point-in-polygon pra conformar com `SelectionStrategy`. Sem mudança de comportamento. Serve de validação do protocolo.

### `GrowStrategy` (novo)

Implementa o algoritmo de grow descrito acima. Métodos relevantes:

- `start(at: GrowOrigin, in: Canvas) -> GrowSession` — cria sessão.
- `GrowSession.tick(deltaTime: TimeInterval) -> GrowFrame` — avança um frame; retorna estado atual (raio, strokes incluídos, próximo candidato, em pausa?).
- `GrowSession.finalize() -> Set<UUID>` — converte estado em seleção final.

`GrowOrigin` é enum: `.stroke(UUID, CGPoint)` ou `.point(CGPoint)`.

### `DensityProbe` (novo, helper interno do `GrowStrategy`)

Calcula o **incremento mínimo de raio** necessário pra incluir o próximo stroke fora da seleção atual. Comparando esse incremento com o passo nominal por tick, decide o **fator de slowdown** (1.0 = velocidade base, 0.1 = pausa profunda).

Implementação simples na primeira versão: spatial index linear (todos os strokes não-incluídos), boa o suficiente pra desenhos típicos (<500 strokes). Otimização (k-d tree, BVH) só se a feature mostrar problema.

### `GrowthVisualization` (SwiftUI overlay — novo)

View SwiftUI que observa um `GrowthVisualizationState` (publicado pelo ViewModel) e desenha:
- Círculo do raio (Path com stroke pontilhado).
- Pulse no candidato (animação opacity em loop).
- Halo dourado quando `isPaused == true`.

Reusa o `SelectionHighlight` existente pros strokes já incluídos — não duplica essa parte.

### `SelectionOverlay` (renomeação de `LassoOverlay`)

A view UIKit que captura gestos vira `SelectionOverlay`. Adiciona:
- `UILongPressGestureRecognizer` (minimumPressDuration: 0.15, allowableMovement: 5pt) → dispara `GrowStrategy`.
- Mantém o reconhecedor de drag → dispara `LassoStrategy`.

Os dois gestures são mutuamente exclusivos via `require(toFail:)` no longPress sobre o pan, garantindo que mover ativa lasso e ficar parado ativa grow.

### `DrawingViewModel` — mudanças mínimas

- Adiciona handlers `growSessionStarted/Updated/Ended`.
- Mantém `selectedStrokeIDs: Set<UUID>` — finalize escreve direto nessa propriedade.
- Publica `growthState: GrowthVisualizationState?` consumido pela view.

## Algoritmo de crescimento (detalhe)

Cada tick (driver: `CADisplayLink` a 60Hz):

1. Calcula `nominalDeltaR = baseSpeed * dt * densityFactor`.
2. Soma ao `currentRadius`.
3. Pra cada stroke não-incluído, mede distância à fronteira atual.
4. Inclui todos os strokes com distância ≤ `currentRadius`.
5. `DensityProbe` calcula `minDeltaRForNextCandidate`. Se for muito maior que `nominalDeltaR`, próximo tick usa `densityFactor = 0.1` (pausa). Se está próximo, `densityFactor = 1.0` (base).
6. `isPaused = densityFactor < 0.3`.
7. Atualiza `growthState` publicado → SwiftUI re-renderiza.

Termina em três condições:
- Usuário solta (Pencil up) → `finalize()`.
- Não há mais strokes pra incluir e raio atingiu máximo (`canvas.diagonal / 2`) → para de crescer mas mantém estado até soltar.
- Cancelamento sistêmico (interrupção, app entra em background) → descarta seleção.

## Testes

Em `PenSculptTests/`:

- **`SelectionStrategyTests.swift`** — protocolo conforma com cenários determinísticos.
- **`LassoStrategyTests.swift`** — porta os testes existentes do `LassoSelection`.
- **`GrowStrategyTests.swift`** (novo):
  - Origem stroke: incluí o próprio stroke no t=0.
  - Origem ponto: incluí strokes a uma distância dada após N ticks.
  - Crescimento monotônico: `currentRadius` nunca diminui.
  - Pausa: cenário com gap explícito → `densityFactor < 0.3` enquanto o gap não é cruzado.
  - Finalize idempotente.
- **`DensityProbeTests.swift`** (novo) — calcula `minDeltaRForNextCandidate` corretamente em layouts simples (linear, cluster, isolado).

Verificação manual no iPad real:
- Casa+janela: tap+hold em traço da janela seleciona apenas a janela quando solto durante a pausa entre janela e parede.
- Tap em área vazia: esfera nasce no ponto, cresce, captura strokes próximos.
- Drag continua disparando laço, sem disparar grow.
- Hold parado dispara grow, sem disparar laço.
- Halo dourado aparece visualmente quando o crescimento entra em pausa.
- Undo após grow reverte a seleção.
- Sair do app durante hold (background) cancela sem confirmar.

## Plano de iteração

Tuning fino dos parâmetros (velocidade base, threshold de pausa, duração do pulse, cor exata do halo) é feito por **iteração via teste manual**, não por especificação prévia. Defaults iniciais estão na seção Algoritmo. Ajustes via constantes claramente nomeadas no topo de `GrowStrategy.swift` e `GrowthVisualization.swift`.

## Ordem de implementação

Dois commits separados pra reduzir risco:

1. **Refator** — extrai `SelectionStrategy` protocol; `LassoSelection` vira `LassoStrategy`. Sem mudança de comportamento. Testes existentes continuam passando.
2. **Feature nova** — `GrowStrategy`, `DensityProbe`, `GrowthVisualization`, `SelectionOverlay` (renomeação + novo gesture), atualizações no `DrawingViewModel`.

Não há mudança de banco de dados, schema ou formato de save — `selectedStrokeIDs` segue como `Set<UUID>` no estado atual.
