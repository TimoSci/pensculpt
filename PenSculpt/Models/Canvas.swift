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
