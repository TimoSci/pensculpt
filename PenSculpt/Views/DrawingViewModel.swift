import Foundation
import Observation

@Observable
class DrawingViewModel {
    var canvas: Canvas
    var selectedTool: DrawingTool = .pen
    var strokeWidth: CGFloat = 3
    var strokeOpacity: CGFloat = 1
    var lastEraserType: DrawingTool = .eraser
    var showToolbar = false
    var showSavedMessage = false
    var autosaveEnabled = true
    var appMode: AppMode = .draw
    var lassoPoints: [CGPoint] = []
    var selectedStrokeIDs: Set<UUID> = []
    var showSculptScreen = false

    init(canvas: Canvas) {
        self.canvas = canvas
    }

    var selectedStrokes: [Stroke] {
        canvas.strokes.filter { selectedStrokeIDs.contains($0.id) }
    }

    var hasSelection: Bool {
        !selectedStrokeIDs.isEmpty
    }

    // MARK: - Mode switching

    func toggleMode() {
        if appMode == .draw {
            appMode = .select
        } else {
            appMode = .draw
            lassoPoints = []
            selectedStrokeIDs = []
        }
    }

    // MARK: - Tool management

    func handlePencilDoubleTap() {
        guard appMode == .draw else { return }
        if selectedTool == .pen {
            selectedTool = lastEraserType
        } else {
            selectedTool = .pen
        }
    }

    func handleToolChange(_ newTool: DrawingTool) {
        if newTool.isEraser {
            lastEraserType = newTool
        }
    }

    // MARK: - Selection

    func handleLassoCompleted(polygon: [CGPoint]) {
        selectedStrokeIDs = LassoSelection.selectedStrokeIDs(
            strokes: canvas.strokes,
            polygon: polygon
        )
    }

    // MARK: - Stroke mutations

    func addStroke(_ stroke: Stroke) {
        canvas.addStroke(stroke)
    }

    func removeStroke(id: UUID) {
        canvas.removeStroke(id: id)
    }

    func clearStrokes() {
        canvas.clearStrokes()
    }
}
