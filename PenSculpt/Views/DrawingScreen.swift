import SwiftUI
import PencilKit

/// Holds a weak reference to the PKCanvasView for coordinate conversion.
class ViewBridge {
    weak var canvasView: PKCanvasView?
}

struct DrawingScreen: View {
    @Binding var documentCanvas: Canvas
    @Binding var drawingData: Data
    @State private var canvas: Canvas
    @State private var pkDrawing = PKDrawing()
    @State private var selectedTool: DrawingTool = .pen
    @State private var strokeWidth: CGFloat = 3
    @State private var strokeOpacity: CGFloat = 1
    @State private var lastEraserType: DrawingTool = .eraser
    @State private var showToolbar = false
    @State private var showSavedMessage = false
    @State private var autosaveEnabled = true
    @State private var appMode: AppMode = .draw
    @State private var lassoPoints: [CGPoint] = []
    @State private var selectedStrokeIDs: Set<UUID> = []
    @State private var showSculptScreen = false
    @State private var drawingSyncTask: Task<Void, Never>?
    @State private var viewBridge = ViewBridge()
    @Environment(\.undoManager) private var undoManager

    init(canvas: Binding<Canvas>, drawingData: Binding<Data>) {
        _documentCanvas = canvas
        _drawingData = drawingData
        _canvas = State(initialValue: canvas.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            canvasLayer
            selectionHighlightLayer
            selectModeOverlay
            if appMode == .draw { drawModeControls }
            if appMode == .select && !selectedStrokeIDs.isEmpty { sculptButton }
        }
        .overlay(alignment: .top) { savedMessageOverlay }
        .fullScreenCover(isPresented: $showSculptScreen) {
            SculptScreen(strokes: selectedStrokes)
        }
        .toolbar { navBarItems }
        .onAppear { loadDrawingData() }
        .onChange(of: canvas) { _, _ in
            guard autosaveEnabled else { return }
            documentCanvas = canvas
        }
        .onChange(of: pkDrawing) { _, newDrawing in
            guard autosaveEnabled else { return }
            debounceSyncDrawing(newDrawing)
        }
        .onChange(of: autosaveEnabled) { _, enabled in
            if enabled { flushToDocument() }
        }
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(.black)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var selectionHighlightLayer: some View {
        if !selectedStrokeIDs.isEmpty {
            SelectionHighlight(strokes: canvas.strokes, selectedIDs: selectedStrokeIDs, viewBridge: viewBridge)
        }
    }

    @ViewBuilder
    private var selectModeOverlay: some View {
        if appMode == .select {
            LassoOverlay(
                lassoPoints: $lassoPoints,
                onLassoCompleted: { canvasPolygon in
                    selectedStrokeIDs = LassoSelection.selectedStrokeIDs(
                        strokes: canvas.strokes,
                        polygon: canvasPolygon
                    )
                },
                viewBridge: viewBridge
            )
            .ignoresSafeArea()
        }
    }

    private var sculptButton: some View {
        Button {
            showSculptScreen = true
        } label: {
            Label("Sculpt", systemImage: "cube")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.blue, in: Capsule())
                .foregroundStyle(.white)
        }
        .padding(.bottom, 30)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var selectedStrokes: [Stroke] {
        canvas.strokes.filter { selectedStrokeIDs.contains($0.id) }
    }

    @ViewBuilder
    private var savedMessageOverlay: some View {
        if showSavedMessage {
            Text("Saved!")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.top, 60)
        }
    }

    private var navBarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if appMode == .draw {
                            appMode = .select
                        } else {
                            appMode = .draw
                            lassoPoints = []
                            selectedStrokeIDs = []
                        }
                    }
                } label: {
                    Image(systemName: appMode == .draw ? "lasso" : "pencil.tip")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }

                Button {
                    withAnimation { autosaveEnabled.toggle() }
                } label: {
                    Image(systemName: autosaveEnabled
                          ? "arrow.triangle.2.circlepath.circle.fill"
                          : "arrow.triangle.2.circlepath.circle")
                        .font(.body)
                        .foregroundStyle(autosaveEnabled ? .primary : .secondary)
                }

                Button {
                    saveToDocument()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.body)
                }
            }
        }
    }

    private var canvasLayer: some View {
        CanvasView(
            drawing: $pkDrawing,
            selectedTool: selectedTool,
            strokeWidth: strokeWidth,
            strokeOpacity: strokeOpacity,
            onStrokeCompleted: { pkStroke in
                let stroke = StrokeConverter.convert(pkStroke)
                addStrokeWithUndo(stroke)
            },
            onStrokeErased: { removedIndices in
                for index in removedIndices.reversed() {
                    guard index < canvas.strokes.count else { continue }
                    removeStrokeWithUndo(canvas.strokes[index])
                }
            },
            isInteractive: appMode == .draw,
            viewBridge: viewBridge
        )
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .pencilDoubleTap)) { _ in
            guard appMode == .draw else { return }
            if selectedTool == .pen {
                selectedTool = lastEraserType
            } else {
                selectedTool = .pen
            }
        }
        .onChange(of: selectedTool) { _, newTool in
            if newTool.isEraser {
                lastEraserType = newTool
            }
        }
    }

    @ViewBuilder
    private var drawModeControls: some View {
        if showToolbar {
            FloatingToolbar(
                selectedTool: $selectedTool,
                strokeWidth: $strokeWidth,
                strokeOpacity: $strokeOpacity,
                onUndo: { undoManager?.undo() },
                onRedo: { undoManager?.redo() },
                onClear: { clearWithUndo() }
            )
            .padding(.bottom, 60)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showToolbar.toggle()
            }
        } label: {
            Image(systemName: showToolbar ? "chevron.down.circle.fill" : "ellipsis.circle")
                .font(.title2)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .padding(.bottom, 16)
    }

    // MARK: - Lifecycle

    private func loadDrawingData() {
        if !drawingData.isEmpty, let loaded = try? PKDrawing(data: drawingData) {
            pkDrawing = loaded
        }
    }

    private func debounceSyncDrawing(_ newDrawing: PKDrawing) {
        drawingSyncTask?.cancel()
        drawingSyncTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            drawingData = newDrawing.dataRepresentation()
        }
    }

    // MARK: - Save

    private func flushToDocument() {
        drawingSyncTask?.cancel()
        documentCanvas = canvas
        drawingData = pkDrawing.dataRepresentation()
    }

    private func saveToDocument() {
        flushToDocument()
        withAnimation { showSavedMessage = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSavedMessage = false }
        }
    }

    // MARK: - Undo-aware actions

    private func addStrokeWithUndo(_ stroke: Stroke) {
        canvas.addStroke(stroke)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            canvas.removeStroke(id: stroke.id)
            // Remove from PencilKit too
            pkDrawing = PKDrawing(strokes: pkDrawing.strokes.dropLast())
        }
    }

    private func removeStrokeWithUndo(_ stroke: Stroke) {
        canvas.removeStroke(id: stroke.id)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            canvas.addStroke(stroke)
        }
    }

    private func clearWithUndo() {
        let previousStrokes = canvas.strokes
        let previousDrawing = pkDrawing
        canvas.clearStrokes()
        pkDrawing = PKDrawing()
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            canvas.strokes = previousStrokes
            pkDrawing = previousDrawing
        }
    }

}

/// A reference type target for UndoManager registration (UndoManager requires AnyObject).
private final class UndoProxy {
    static let shared = UndoProxy()
}
