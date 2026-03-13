# PenSculpt Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working iPad drawing app with Apple Pencil support — black and white, undo/redo, eraser, save/load — with an internal stroke model ready for Stage 2's 3D features.

**Architecture:** SwiftUI app shell hosting a PencilKit PKCanvasView for drawing. Strokes are captured via PencilKit and converted to an internal Stroke model on completion. Document persistence via ReferenceFileDocument with a .pensculpt package format.

**Tech Stack:** Swift, SwiftUI, UIKit (PKCanvasView bridge), PencilKit, Codable, XCTest

**Spec:** `docs/superpowers/specs/2026-03-13-pensculpt-design.md`

---

## File Structure

```
PenSculpt/
├── PenSculpt.xcodeproj
├── PenSculpt/
│   ├── App/
│   │   └── PenSculptApp.swift              # App entry, DocumentGroup scene
│   ├── Models/
│   │   ├── StrokePoint.swift               # Per-point data (position, pressure, tilt, azimuth, timestamp)
│   │   ├── Stroke.swift                    # Collection of StrokePoints + color + id
│   │   └── Canvas.swift                    # Document root: dimensions, strokes list
│   ├── Drawing/
│   │   ├── CanvasView.swift                # UIViewRepresentable wrapping PKCanvasView
│   │   └── StrokeConverter.swift           # PKStroke → Stroke conversion
│   ├── Views/
│   │   ├── DrawingScreen.swift             # Full-screen drawing view, hosts CanvasView
│   │   └── FloatingToolbar.swift           # Minimal floating toolbar (undo/redo/clear/eraser)
│   ├── Persistence/
│   │   └── PenSculptDocument.swift         # ReferenceFileDocument, .pensculpt package format
│   └── Resources/
│       └── Info.plist                      # UTI declarations for .pensculpt
├── PenSculptTests/
│   ├── StrokePointTests.swift
│   ├── StrokeTests.swift
│   ├── CanvasTests.swift
│   ├── StrokeConverterTests.swift
│   └── PenSculptDocumentTests.swift
└── guides/
    └── 01-drawing-basics.md                # Human-readable feature guide
```

---

## Chunk 1: Project Setup + Data Model

### Task 1: Create Xcode Project

**Files:**
- Create: `PenSculpt.xcodeproj` (via xcodegen or manual)
- Create: `PenSculpt/App/PenSculptApp.swift`
- Create: `project.yml` (xcodegen spec)

- [ ] **Step 1: Install xcodegen if needed**

Run: `which xcodegen || brew install xcodegen`

- [ ] **Step 2: Create project.yml**

```yaml
name: PenSculpt
options:
  bundleIdPrefix: com.pensculpt
  deploymentTarget:
    iPad: "17.0"
  xcodeVersion: "16.0"
settings:
  TARGETED_DEVICE_FAMILY: 2
  SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: false
  SWIFT_VERSION: "5.9"
targets:
  PenSculpt:
    type: application
    platform: iOS
    sources:
      - PenSculpt
    settings:
      INFOPLIST_FILE: PenSculpt/Resources/Info.plist
      PRODUCT_BUNDLE_IDENTIFIER: com.pensculpt.app
    scheme:
      testTargets:
        - PenSculptTests
  PenSculptTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - PenSculptTests
    dependencies:
      - target: PenSculpt
    settings:
      TEST_HOST: "$(BUILT_PRODUCTS_DIR)/PenSculpt.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PenSculpt"
      BUNDLE_LOADER: "$(TEST_HOST)"
```

- [ ] **Step 3: Create minimal app entry point**

Create `PenSculpt/App/PenSculptApp.swift`:
```swift
import SwiftUI

@main
struct PenSculptApp: App {
    var body: some Scene {
        WindowGroup {
            Text("PenSculpt")
        }
    }
}
```

- [ ] **Step 4: Create Info.plist with UTI declarations**

Create `PenSculpt/Resources/Info.plist` with exported UTI for `com.pensculpt.document` mapped to `.pensculpt` extension.

- [ ] **Step 5: Generate Xcode project and verify build**

Run: `cd /Users/me/Documents/code/pensculpt && xcodegen generate`
Run: `xcodebuild -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add project.yml PenSculpt/ PenSculptTests/ PenSculpt.xcodeproj
git commit -m "feat: initialize Xcode project with iPad target"
```

---

### Task 2: StrokePoint and Stroke Models

**Files:**
- Create: `PenSculpt/Models/StrokePoint.swift`
- Create: `PenSculpt/Models/Stroke.swift`
- Create: `PenSculptTests/StrokePointTests.swift`
- Create: `PenSculptTests/StrokeTests.swift`

- [ ] **Step 1: Write StrokePoint tests**

Create `PenSculptTests/StrokePointTests.swift`:
```swift
import XCTest
@testable import PenSculpt

final class StrokePointTests: XCTestCase {

    func testInitialization() {
        let point = StrokePoint(
            location: CGPoint(x: 100, y: 200),
            pressure: 0.5,
            tilt: 0.3,
            azimuth: 1.2,
            timestamp: 1000.0
        )
        XCTAssertEqual(point.location, CGPoint(x: 100, y: 200))
        XCTAssertEqual(point.pressure, 0.5)
        XCTAssertEqual(point.tilt, 0.3)
        XCTAssertEqual(point.azimuth, 1.2)
        XCTAssertEqual(point.timestamp, 1000.0)
    }

    func testCodable() throws {
        let point = StrokePoint(
            location: CGPoint(x: 50, y: 75),
            pressure: 0.8,
            tilt: 0.1,
            azimuth: 0.5,
            timestamp: 500.0
        )
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(StrokePoint.self, from: data)
        XCTAssertEqual(decoded.location, point.location)
        XCTAssertEqual(decoded.pressure, point.pressure)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project PenSculpt.xcodeproj -scheme PenSculpt -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' -only-testing:PenSculptTests/StrokePointTests 2>&1 | tail -5`
Expected: FAIL — StrokePoint not defined

- [ ] **Step 3: Implement StrokePoint**

Create `PenSculpt/Models/StrokePoint.swift`:
```swift
import Foundation

struct StrokePoint: Codable, Equatable, Sendable {
    let location: CGPoint
    let pressure: CGFloat
    let tilt: CGFloat
    let azimuth: CGFloat
    let timestamp: TimeInterval
}
```

- [ ] **Step 4: Run test to verify it passes**

Expected: PASS

- [ ] **Step 5: Write Stroke tests**

Create `PenSculptTests/StrokeTests.swift`:
```swift
import XCTest
@testable import PenSculpt

final class StrokeTests: XCTestCase {

    func testInitWithDefaults() {
        let stroke = Stroke(points: [])
        XCTAssertEqual(stroke.color, .black)
        XCTAssertTrue(stroke.points.isEmpty)
        XCTAssertFalse(stroke.id.uuidString.isEmpty)
    }

    func testInitWithPoints() {
        let points = [
            StrokePoint(location: .zero, pressure: 1.0, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 10, y: 10), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0.1)
        ]
        let stroke = Stroke(points: points)
        XCTAssertEqual(stroke.points.count, 2)
    }

    func testBoundingBox() {
        let points = [
            StrokePoint(location: CGPoint(x: 10, y: 20), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0),
            StrokePoint(location: CGPoint(x: 50, y: 80), pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ]
        let stroke = Stroke(points: points)
        let bounds = stroke.boundingBox
        XCTAssertEqual(bounds.origin.x, 10)
        XCTAssertEqual(bounds.origin.y, 20)
        XCTAssertEqual(bounds.width, 40)
        XCTAssertEqual(bounds.height, 60)
    }

    func testCodable() throws {
        let stroke = Stroke(points: [
            StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        let data = try JSONEncoder().encode(stroke)
        let decoded = try JSONDecoder().decode(Stroke.self, from: data)
        XCTAssertEqual(decoded.id, stroke.id)
        XCTAssertEqual(decoded.points.count, 1)
        XCTAssertEqual(decoded.color, .black)
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Expected: FAIL — Stroke not defined

- [ ] **Step 7: Implement Stroke**

Create `PenSculpt/Models/Stroke.swift`:
```swift
import SwiftUI

struct Stroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var points: [StrokePoint]
    var color: CodableColor

    init(id: UUID = UUID(), points: [StrokePoint], color: CodableColor = .black) {
        self.id = id
        self.points = points
        self.color = color
    }

    var boundingBox: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.location.x
        var minY = first.location.y
        var maxX = minX
        var maxY = minY
        for point in points.dropFirst() {
            minX = min(minX, point.location.x)
            minY = min(minY, point.location.y)
            maxX = max(maxX, point.location.x)
            maxY = max(maxY, point.location.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct CodableColor: Codable, Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
}
```

- [ ] **Step 8: Run all tests**

Expected: ALL PASS

- [ ] **Step 9: Commit**

```bash
git add PenSculpt/Models/ PenSculptTests/StrokePointTests.swift PenSculptTests/StrokeTests.swift
git commit -m "feat: add StrokePoint and Stroke models with Codable support"
```

---

### Task 3: Canvas Model

**Files:**
- Create: `PenSculpt/Models/Canvas.swift`
- Create: `PenSculptTests/CanvasTests.swift`

- [ ] **Step 1: Write Canvas tests**

Create `PenSculptTests/CanvasTests.swift`:
```swift
import XCTest
@testable import PenSculpt

final class CanvasTests: XCTestCase {

    func testInitEmpty() {
        let canvas = Canvas()
        XCTAssertTrue(canvas.strokes.isEmpty)
        XCTAssertEqual(canvas.size, CGSize(width: 1024, height: 1366))
    }

    func testAddStroke() {
        var canvas = Canvas()
        let stroke = Stroke(points: [
            StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        canvas.addStroke(stroke)
        XCTAssertEqual(canvas.strokes.count, 1)
        XCTAssertEqual(canvas.strokes.first?.id, stroke.id)
    }

    func testRemoveStroke() {
        var canvas = Canvas()
        let stroke = Stroke(points: [
            StrokePoint(location: .zero, pressure: 1, tilt: 0, azimuth: 0, timestamp: 0)
        ])
        canvas.addStroke(stroke)
        canvas.removeStroke(id: stroke.id)
        XCTAssertTrue(canvas.strokes.isEmpty)
    }

    func testClearStrokes() {
        var canvas = Canvas()
        canvas.addStroke(Stroke(points: []))
        canvas.addStroke(Stroke(points: []))
        canvas.clearStrokes()
        XCTAssertTrue(canvas.strokes.isEmpty)
    }

    func testCodable() throws {
        var canvas = Canvas()
        canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 5, y: 5), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 1)
        ]))
        let data = try JSONEncoder().encode(canvas)
        let decoded = try JSONDecoder().decode(Canvas.self, from: data)
        XCTAssertEqual(decoded.strokes.count, 1)
        XCTAssertEqual(decoded.size, canvas.size)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement Canvas**

Create `PenSculpt/Models/Canvas.swift`:
```swift
import Foundation

struct Canvas: Codable, Equatable, Sendable {
    var size: CGSize
    var strokes: [Stroke]

    init(size: CGSize = CGSize(width: 1024, height: 1366)) {
        self.size = size
        self.strokes = []
    }

    mutating func addStroke(_ stroke: Stroke) {
        strokes.append(stroke)
    }

    mutating func removeStroke(id: UUID) {
        strokes.removeAll { $0.id == id }
    }

    mutating func clearStrokes() {
        strokes.removeAll()
    }
}
```

- [ ] **Step 4: Run tests — expect ALL PASS**

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Models/Canvas.swift PenSculptTests/CanvasTests.swift
git commit -m "feat: add Canvas model with stroke management"
```

---

## Chunk 2: Drawing Engine

### Task 4: StrokeConverter — PKStroke to Stroke

**Files:**
- Create: `PenSculpt/Drawing/StrokeConverter.swift`
- Create: `PenSculptTests/StrokeConverterTests.swift`

- [ ] **Step 1: Write StrokeConverter tests**

Create `PenSculptTests/StrokeConverterTests.swift`:
```swift
import XCTest
import PencilKit
@testable import PenSculpt

final class StrokeConverterTests: XCTestCase {

    func testConvertPKStroke() {
        // Create a PKStroke programmatically
        let points = [
            PKStrokePoint(location: CGPoint(x: 0, y: 0), timeOffset: 0,
                          size: CGSize(width: 5, height: 5), opacity: 1,
                          force: 0.5, azimuth: 0, altitude: .pi / 4),
            PKStrokePoint(location: CGPoint(x: 100, y: 100), timeOffset: 0.1,
                          size: CGSize(width: 5, height: 5), opacity: 1,
                          force: 0.8, azimuth: 0.5, altitude: .pi / 3)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKInk(.pen, color: .black)
        let pkStroke = PKStroke(ink: ink, path: path)

        let stroke = StrokeConverter.convert(pkStroke)

        XCTAssertEqual(stroke.points.count, 2)
        XCTAssertEqual(stroke.points[0].location, CGPoint(x: 0, y: 0))
        XCTAssertEqual(stroke.points[0].pressure, 0.5)
        XCTAssertEqual(stroke.points[1].location, CGPoint(x: 100, y: 100))
        XCTAssertEqual(stroke.color, .black)
    }

    func testConvertPKDrawing() {
        let points = [
            PKStrokePoint(location: CGPoint(x: 0, y: 0), timeOffset: 0,
                          size: CGSize(width: 5, height: 5), opacity: 1,
                          force: 1, azimuth: 0, altitude: .pi / 4)
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKInk(.pen, color: .black)
        let pkStroke = PKStroke(ink: ink, path: path)
        let drawing = PKDrawing(strokes: [pkStroke])

        let strokes = StrokeConverter.convertAll(drawing)

        XCTAssertEqual(strokes.count, 1)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement StrokeConverter**

Create `PenSculpt/Drawing/StrokeConverter.swift`:
```swift
import PencilKit

enum StrokeConverter {

    static func convert(_ pkStroke: PKStroke) -> Stroke {
        let path = pkStroke.path
        var points: [StrokePoint] = []
        points.reserveCapacity(path.count)

        for i in 0..<path.count {
            let p = path[i]
            points.append(StrokePoint(
                location: p.location,
                pressure: p.force,
                tilt: p.altitude,
                azimuth: p.azimuth,
                timestamp: p.timeOffset
            ))
        }

        return Stroke(points: points, color: .black)
    }

    static func convertAll(_ drawing: PKDrawing) -> [Stroke] {
        drawing.strokes.map { convert($0) }
    }
}
```

- [ ] **Step 4: Run tests — expect ALL PASS**

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Drawing/StrokeConverter.swift PenSculptTests/StrokeConverterTests.swift
git commit -m "feat: add StrokeConverter for PKStroke to Stroke conversion"
```

---

### Task 5: PencilKit Canvas View

**Files:**
- Create: `PenSculpt/Drawing/CanvasView.swift`

- [ ] **Step 1: Implement CanvasView (UIViewRepresentable)**

Create `PenSculpt/Drawing/CanvasView.swift`:
```swift
import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var tool: PKTool
    var onStrokeCompleted: ((PKStroke) -> Void)?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.delegate = context.coordinator
        canvasView.overrideUserInterfaceStyle = .light
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if canvasView.tool.description != tool.description {
            canvasView.tool = tool
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: CanvasView
        private var previousStrokeCount = 0

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            let currentCount = canvasView.drawing.strokes.count
            if currentCount > previousStrokeCount,
               let lastStroke = canvasView.drawing.strokes.last {
                parent.onStrokeCompleted?(lastStroke)
            }
            previousStrokeCount = currentCount
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build ...`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/Drawing/CanvasView.swift
git commit -m "feat: add PencilKit CanvasView with stroke completion callback"
```

---

### Task 6: Floating Toolbar

**Files:**
- Create: `PenSculpt/Views/FloatingToolbar.swift`

- [ ] **Step 1: Implement FloatingToolbar**

Create `PenSculpt/Views/FloatingToolbar.swift`:
```swift
import SwiftUI

enum DrawingTool: String, CaseIterable {
    case pen
    case eraser
}

struct FloatingToolbar: View {
    @Binding var selectedTool: DrawingTool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }

            Divider().frame(height: 24)

            ForEach(DrawingTool.allCases, id: \.self) { tool in
                Button {
                    selectedTool = tool
                } label: {
                    Image(systemName: tool == .pen ? "pencil.tip" : "eraser")
                        .foregroundStyle(selectedTool == tool ? .primary : .secondary)
                }
            }

            Divider().frame(height: 24)

            Button(action: onClear) {
                Image(systemName: "trash")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
```

- [ ] **Step 2: Verify build**

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/Views/FloatingToolbar.swift
git commit -m "feat: add floating toolbar with undo/redo/eraser/clear"
```

---

### Task 7: Drawing Screen — Main View

**Files:**
- Create: `PenSculpt/Views/DrawingScreen.swift`

- [ ] **Step 1: Implement DrawingScreen**

Create `PenSculpt/Views/DrawingScreen.swift`:
```swift
import SwiftUI
import PencilKit

struct DrawingScreen: View {
    @Binding var canvas: Canvas
    @State private var pkDrawing = PKDrawing()
    @State private var selectedTool: DrawingTool = .pen
    @State private var showToolbar = false
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ZStack(alignment: .bottom) {
            CanvasView(
                drawing: $pkDrawing,
                tool: pkToolBinding,
                onStrokeCompleted: { pkStroke in
                    let stroke = StrokeConverter.convert(pkStroke)
                    canvas.addStroke(stroke)
                }
            )
            .ignoresSafeArea()
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.startLocation.x < 20 {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showToolbar.toggle()
                            }
                        }
                    }
            )

            if showToolbar {
                FloatingToolbar(
                    selectedTool: $selectedTool,
                    onUndo: { undoManager?.undo() },
                    onRedo: { undoManager?.redo() },
                    onClear: {
                        pkDrawing = PKDrawing()
                        canvas.clearStrokes()
                    }
                )
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var pkToolBinding: Binding<PKTool> {
        Binding(
            get: {
                switch selectedTool {
                case .pen:
                    return PKInkingTool(.pen, color: .black, width: 3)
                case .eraser:
                    return PKEraserTool(.vector)
                }
            },
            set: { _ in }
        )
    }
}
```

- [ ] **Step 2: Verify build**

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/Views/DrawingScreen.swift
git commit -m "feat: add DrawingScreen with edge-swipe toolbar and PencilKit canvas"
```

---

## Chunk 3: Persistence + App Integration

### Task 8: PenSculptDocument

**Files:**
- Create: `PenSculpt/Persistence/PenSculptDocument.swift`
- Create: `PenSculptTests/PenSculptDocumentTests.swift`

- [ ] **Step 1: Write document tests**

Create `PenSculptTests/PenSculptDocumentTests.swift`:
```swift
import XCTest
@testable import PenSculpt

final class PenSculptDocumentTests: XCTestCase {

    func testNewDocumentHasEmptyCanvas() {
        let doc = PenSculptDocument()
        XCTAssertTrue(doc.canvas.strokes.isEmpty)
    }

    func testSnapshotRoundTrip() throws {
        let doc = PenSculptDocument()
        doc.canvas.addStroke(Stroke(points: [
            StrokePoint(location: CGPoint(x: 1, y: 2), pressure: 0.5, tilt: 0, azimuth: 0, timestamp: 0)
        ]))

        let data = try JSONEncoder().encode(doc.canvas)
        let decoded = try JSONDecoder().decode(Canvas.self, from: data)
        XCTAssertEqual(decoded.strokes.count, 1)
    }
}
```

- [ ] **Step 2: Run tests — expect FAIL**

- [ ] **Step 3: Implement PenSculptDocument**

Create `PenSculpt/Persistence/PenSculptDocument.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pensculpt = UTType(exportedAs: "com.pensculpt.document")
}

final class PenSculptDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.pensculpt] }
    static var writableContentTypes: [UTType] { [.pensculpt] }

    @Published var canvas: Canvas

    init() {
        self.canvas = Canvas()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.canvas = try JSONDecoder().decode(Canvas.self, from: data)
    }

    func snapshot(contentType: UTType) throws -> Data {
        try JSONEncoder().encode(canvas)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
```

- [ ] **Step 4: Run tests — expect ALL PASS**

- [ ] **Step 5: Commit**

```bash
git add PenSculpt/Persistence/ PenSculptTests/PenSculptDocumentTests.swift
git commit -m "feat: add PenSculptDocument with .pensculpt file format"
```

---

### Task 9: Wire App Together

**Files:**
- Modify: `PenSculpt/App/PenSculptApp.swift`

- [ ] **Step 1: Update PenSculptApp to use DocumentGroup**

```swift
import SwiftUI

@main
struct PenSculptApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PenSculptDocument() }) { config in
            DrawingScreen(canvas: Binding(
                get: { config.document.canvas },
                set: { config.document.canvas = $0 }
            ))
        }
    }
}
```

- [ ] **Step 2: Verify build**

- [ ] **Step 3: Commit**

```bash
git add PenSculpt/App/PenSculptApp.swift
git commit -m "feat: wire DocumentGroup with DrawingScreen for save/load"
```

---

### Task 10: Feature Guide + TODO.md

**Files:**
- Create: `guides/01-drawing-basics.md`
- Create: `TODO.md`
- Create: `AGENTS.md`

- [ ] **Step 1: Write drawing basics guide**

Create `guides/01-drawing-basics.md` — human-readable documentation of Stage 1 drawing features: how to draw, use the toolbar, undo/redo, eraser, save/load, Apple Pencil double-tap and hover support.

- [ ] **Step 2: Create TODO.md**

Create `TODO.md` tracking all features with completed / code-optimized / code-simplified statuses.

- [ ] **Step 3: Create AGENTS.md**

Create `AGENTS.md` with instructions for future agents/models continuing development — project overview, architecture decisions, how to build/test, conventions, and pointers to spec and plan docs.

- [ ] **Step 4: Commit**

```bash
git add guides/ TODO.md AGENTS.md
git commit -m "docs: add drawing guide, TODO tracking, and agent instructions"
```

---

## Chunk 4: Stage 2 — Selection System

### Task 11: SelectionStrategy Protocol + StrokeGroup Model

**Files:**
- Create: `PenSculpt/Selection/SelectionStrategy.swift`
- Create: `PenSculpt/Models/StrokeGroup.swift`

- [ ] **Step 1: Write tests for StrokeGroup and SelectionStrategy**
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement SelectionStrategy protocol and StrokeGroup**

```swift
// SelectionStrategy.swift
import Foundation

protocol SelectionStrategy {
    func selectedStrokes(from strokes: [Stroke], with input: SelectionInput) -> [Stroke]
}

enum SelectionInput {
    case lasso(points: [CGPoint])
    case tap(point: CGPoint, duration: TimeInterval)
}
```

```swift
// StrokeGroup.swift
struct StrokeGroup: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var strokeIDs: [UUID]

    init(id: UUID = UUID(), strokeIDs: [UUID]) {
        self.id = id
        self.strokeIDs = strokeIDs
    }
}
```

- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 12: LassoSelection Implementation

**Files:**
- Create: `PenSculpt/Selection/LassoSelection.swift`
- Create: `PenSculptTests/LassoSelectionTests.swift`

- [ ] **Step 1: Write lasso selection tests**

Test cases: point-in-polygon, 50% threshold, auto-close behavior, empty lasso, strokes fully inside, strokes partially inside (below/above threshold).

- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement LassoSelection**

Point-in-polygon via ray casting algorithm. Count stroke points inside polygon. Include stroke if >= 50%.

- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 13: Selection UI Integration

**Files:**
- Modify: `PenSculpt/Views/FloatingToolbar.swift` — add Select mode toggle
- Create: `PenSculpt/Views/LassoOverlay.swift` — draws the lasso path
- Modify: `PenSculpt/Views/DrawingScreen.swift` — handle selection mode

- [ ] **Step 1: Add select mode to toolbar and DrawingScreen**
- [ ] **Step 2: Implement LassoOverlay for visual feedback**
- [ ] **Step 3: Wire lasso selection into DrawingScreen**
- [ ] **Step 4: Verify build**
- [ ] **Step 5: Commit**

---

## Chunk 5: Stage 2 — Inference Pipeline

### Task 14: ContourAnalyzer

**Files:**
- Create: `PenSculpt/Inference/ContourAnalyzer.swift`
- Create: `PenSculptTests/ContourAnalyzerTests.swift`

- [ ] **Step 1: Write tests** — extract silhouette from stroke points, handle gaps, produce closed boundary
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — rasterize strokes to 512x512 bitmap, flood-fill exterior, extract boundary pixels as ordered contour
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 15: SkeletonExtractor

**Files:**
- Create: `PenSculpt/Inference/SkeletonExtractor.swift`
- Create: `PenSculptTests/SkeletonExtractorTests.swift`

- [ ] **Step 1: Write tests** — simple rectangle produces single medial line, T-shape produces branch point, circle produces center point
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — distance transform on binary bitmap, Zhang-Suen thinning, extract skeleton graph (nodes + edges)
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 16: Segmenter

**Files:**
- Create: `PenSculpt/Inference/Segmenter.swift`
- Create: `PenSculptTests/SegmenterTests.swift`

- [ ] **Step 1: Write tests** — segment at branch points, segment at high curvature (>45 deg)
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — walk skeleton graph, split at branch nodes and curvature threshold
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 17: PrimitiveFitter

**Files:**
- Create: `PenSculpt/Inference/PrimitiveFitter.swift`
- Create: `PenSculptTests/PrimitiveFitterTests.swift`

- [ ] **Step 1: Write tests** — circular cross-section → cylinder, rectangular → box, tapered → cone, thin → extruded plane, ambiguous → ellipsoid
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — sample cross-sections perpendicular to skeleton, compute circularity/aspect-ratio/taper-ratio, classify per spec thresholds
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 18: MeshAssembler (Marching Cubes)

**Files:**
- Create: `PenSculpt/Inference/MeshAssembler.swift`
- Create: `PenSculpt/Inference/MarchingCubes.swift`
- Create: `PenSculptTests/MeshAssemblerTests.swift`

- [ ] **Step 1: Write tests** — single sphere field → sphere-like mesh, two overlapping spheres → blended mesh, vertex/index counts reasonable
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — each primitive as scalar field, sum fields, extract iso-surface via Marching Cubes at 64^3 grid
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 19: StrokeMapper

**Files:**
- Create: `PenSculpt/Inference/StrokeMapper.swift`
- Create: `PenSculptTests/StrokeMapperTests.swift`

- [ ] **Step 1: Write tests** — project stroke onto flat plane mesh, project onto sphere, handle seam splitting
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — orthographic ray casting from original viewing angle, front-face intersection, UV mapping, seam splitting
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 20: SculptObject Model + InferencePipeline Coordinator

**Files:**
- Create: `PenSculpt/Models/SculptObject.swift`
- Create: `PenSculpt/Inference/InferencePipeline.swift`
- Create: `PenSculptTests/InferencePipelineTests.swift`

- [ ] **Step 1: Write tests** — end-to-end: strokes in → SculptObject with mesh out, fallback on sparse strokes
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement SculptObject** — holds StrokeGroup, mesh vertices/indices, corrections, distortions
- [ ] **Step 4: Implement InferencePipeline** — orchestrates ContourAnalyzer → SkeletonExtractor → Segmenter → PrimitiveFitter → MeshAssembler → StrokeMapper, async execution, fallback to flat plane on failure
- [ ] **Step 5: Run tests — expect ALL PASS**
- [ ] **Step 6: Commit**

---

## Chunk 6: Stage 2 — Metal Renderer

### Task 21: Metal Renderer Setup

**Files:**
- Create: `PenSculpt/Renderer/MetalCanvasView.swift`
- Create: `PenSculpt/Renderer/Renderer.swift`
- Create: `PenSculpt/Resources/Shaders.metal`

- [ ] **Step 1: Implement basic Metal renderer** — MTKView subclass, render pipeline, orthographic camera, clear to white
- [ ] **Step 2: Add mesh rendering** — vertex/index buffer from SculptObject mesh, basic diffuse lighting, sketch aesthetic
- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

---

### Task 22: Stroke Rendering on 3D Surface

**Files:**
- Modify: `PenSculpt/Resources/Shaders.metal`
- Create: `PenSculpt/Renderer/StrokeRenderer.swift`

- [ ] **Step 1: Implement stroke-as-triangle-strip renderer** — generate triangle strips from mapped 3D stroke points, per-vertex width from pressure
- [ ] **Step 2: Add screen-space vs surface-space toggle** — uniform switch in vertex shader, dot(normal, viewDir) modulation for surface-space
- [ ] **Step 3: Verify build**
- [ ] **Step 4: Commit**

---

### Task 23: Rotation + Input Handling

**Files:**
- Create: `PenSculpt/Renderer/InputHandler.swift`
- Modify: `PenSculpt/Renderer/MetalCanvasView.swift`

- [ ] **Step 1: Implement rotation** — two-finger drag → arcball rotation, update model matrix
- [ ] **Step 2: Implement pen-draws-on-surface** — ray cast from pen touch to mesh, add stroke at intersection point, bake onto surface at current viewing angle
- [ ] **Step 3: Add thumb-button for pen-rotate mode**
- [ ] **Step 4: Verify build**
- [ ] **Step 5: Commit**

---

### Task 24: Mesh Deformation (Soft Brush)

**Files:**
- Create: `PenSculpt/Renderer/MeshDeformer.swift`
- Create: `PenSculptTests/MeshDeformerTests.swift`

- [ ] **Step 1: Write tests** — deform single vertex, Gaussian falloff, push/pull direction
- [ ] **Step 2: Run tests — expect FAIL**
- [ ] **Step 3: Implement** — pen contact → deformation center, pressure → radius, screen-space drag → surface-normal push/pull, Gaussian falloff
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

## Chunk 7: Integration + Polish

### Task 25: Sculpt Mode Integration

**Files:**
- Modify: `PenSculpt/Views/DrawingScreen.swift`
- Create: `PenSculpt/Views/SculptScreen.swift`

- [ ] **Step 1: Create SculptScreen** — hosts MetalCanvasView, shows active SculptObject, dimmed inactive objects
- [ ] **Step 2: Wire mode switching** — after lasso confirm → run inference → transition to SculptScreen
- [ ] **Step 3: Add re-inference** — double-tap triggers async re-inference with cross-fade
- [ ] **Step 4: Verify build**
- [ ] **Step 5: Commit**

---

### Task 26: Update Persistence for Stage 2

**Files:**
- Modify: `PenSculpt/Persistence/PenSculptDocument.swift`
- Modify: `PenSculpt/Models/Canvas.swift`

- [ ] **Step 1: Add SculptObject list to Canvas model**
- [ ] **Step 2: Update document serialization** — include sculpt_objects with mesh.bin binary format
- [ ] **Step 3: Write tests for round-trip with SculptObjects**
- [ ] **Step 4: Run tests — expect ALL PASS**
- [ ] **Step 5: Commit**

---

### Task 27: Stage 2 Feature Guide + Update TODO

**Files:**
- Create: `guides/02-sculpt-mode.md`
- Modify: `TODO.md`

- [ ] **Step 1: Write sculpt mode guide** — how to select strokes, enter sculpt mode, rotate, draw corrections, distort mesh, re-infer, stroke style toggle
- [ ] **Step 2: Update TODO.md** — mark Stage 2 items
- [ ] **Step 3: Commit**

```bash
git add guides/02-sculpt-mode.md TODO.md
git commit -m "docs: add sculpt mode guide and update TODO"
```
