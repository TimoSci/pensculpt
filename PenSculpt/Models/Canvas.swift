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
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            strokes.remove(at: index)
        }
    }

    mutating func clearStrokes() {
        strokes.removeAll()
    }
}
