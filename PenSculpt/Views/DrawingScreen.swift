import SwiftUI
import PencilKit

/// Holds a weak reference to the PKCanvasView for coordinate conversion.
class ViewBridge {
    weak var canvasView: PKCanvasView?
}

struct DrawingScreen: View {
    @Binding var documentCanvas: Canvas
    @Binding var drawingData: Data
    @State private var vm: DrawingViewModel
    @State private var pkDrawing = PKDrawing()
    @State private var drawingSyncTask: Task<Void, Never>?
    @State private var viewBridge = ViewBridge()
    @Environment(\.undoManager) private var undoManager

    init(canvas: Binding<Canvas>, drawingData: Binding<Data>) {
        _documentCanvas = canvas
        _drawingData = drawingData
        _vm = State(initialValue: DrawingViewModel(canvas: canvas.wrappedValue))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            canvasLayer
            selectionHighlightLayer
            selectModeOverlay
            if vm.appMode == .draw { drawModeControls }
            if vm.appMode == .select && vm.hasSelection { sculptButton }
        }
        .overlay(alignment: .top) { savedMessageOverlay }
        .fullScreenCover(isPresented: $vm.showSculptScreen) {
            SculptScreen(strokes: vm.selectedStrokes)
        }
        .toolbar { navBarItems }
        .onAppear { loadDrawingData() }
        .onChange(of: vm.canvas) { _, _ in
            guard vm.autosaveEnabled else { return }
            documentCanvas = vm.canvas
        }
        .onChange(of: pkDrawing) { _, newDrawing in
            guard vm.autosaveEnabled else { return }
            debounceSyncDrawing(newDrawing)
        }
        .onChange(of: vm.autosaveEnabled) { _, enabled in
            if enabled { flushToDocument() }
        }
        .onChange(of: vm.selectedTool) { _, newTool in
            vm.handleToolChange(newTool)
        }
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(.black)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var selectionHighlightLayer: some View {
        if vm.hasSelection {
            SelectionHighlight(strokes: vm.canvas.strokes, selectedIDs: vm.selectedStrokeIDs, viewBridge: viewBridge)
        }
    }

    @ViewBuilder
    private var selectModeOverlay: some View {
        if vm.appMode == .select {
            LassoOverlay(
                lassoPoints: $vm.lassoPoints,
                onLassoCompleted: { canvasPolygon in
                    vm.handleLassoCompleted(polygon: canvasPolygon)
                },
                viewBridge: viewBridge
            )
            .ignoresSafeArea()
        }
    }

    private var sculptButton: some View {
        Button {
            vm.showSculptScreen = true
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

    @ViewBuilder
    private var savedMessageOverlay: some View {
        if vm.showSavedMessage {
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
                        vm.toggleMode()
                    }
                } label: {
                    Image(systemName: vm.appMode == .draw ? "lasso" : "pencil.tip")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }

                Button {
                    withAnimation { vm.autosaveEnabled.toggle() }
                } label: {
                    Image(systemName: vm.autosaveEnabled
                          ? "arrow.triangle.2.circlepath.circle.fill"
                          : "arrow.triangle.2.circlepath.circle")
                        .font(.body)
                        .foregroundStyle(vm.autosaveEnabled ? .primary : .secondary)
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
            selectedTool: vm.selectedTool,
            strokeWidth: vm.strokeWidth,
            strokeOpacity: vm.strokeOpacity,
            onStrokeCompleted: { pkStroke in
                let stroke = StrokeConverter.convert(pkStroke)
                addStrokeWithUndo(stroke)
            },
            onStrokeErased: { removedIndices in
                for index in removedIndices.reversed() {
                    guard index < vm.canvas.strokes.count else { continue }
                    removeStrokeWithUndo(vm.canvas.strokes[index])
                }
            },
            isInteractive: vm.appMode == .draw,
            viewBridge: viewBridge
        )
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .pencilDoubleTap)) { _ in
            vm.handlePencilDoubleTap()
        }
    }

    @ViewBuilder
    private var drawModeControls: some View {
        if vm.showToolbar {
            FloatingToolbar(
                selectedTool: $vm.selectedTool,
                strokeWidth: $vm.strokeWidth,
                strokeOpacity: $vm.strokeOpacity,
                onUndo: { undoManager?.undo() },
                onRedo: { undoManager?.redo() },
                onClear: { clearWithUndo() }
            )
            .padding(.bottom, 60)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }

        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                vm.showToolbar.toggle()
            }
        } label: {
            Image(systemName: vm.showToolbar ? "chevron.down.circle.fill" : "ellipsis.circle")
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
        documentCanvas = vm.canvas
        drawingData = pkDrawing.dataRepresentation()
    }

    private func saveToDocument() {
        flushToDocument()
        withAnimation { vm.showSavedMessage = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { vm.showSavedMessage = false }
        }
    }

    // MARK: - Undo-aware actions

    private func addStrokeWithUndo(_ stroke: Stroke) {
        vm.addStroke(stroke)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            vm.removeStroke(id: stroke.id)
            pkDrawing = PKDrawing(strokes: pkDrawing.strokes.dropLast())
        }
    }

    private func removeStrokeWithUndo(_ stroke: Stroke) {
        vm.removeStroke(id: stroke.id)
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            vm.addStroke(stroke)
        }
    }

    private func clearWithUndo() {
        let previousStrokes = vm.canvas.strokes
        let previousDrawing = pkDrawing
        vm.clearStrokes()
        pkDrawing = PKDrawing()
        undoManager?.registerUndo(withTarget: UndoProxy.shared) { _ in
            vm.canvas.strokes = previousStrokes
            pkDrawing = previousDrawing
        }
    }
}

/// A reference type target for UndoManager registration (UndoManager requires AnyObject).
private final class UndoProxy {
    static let shared = UndoProxy()
}
