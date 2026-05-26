import Foundation

struct Canvas: Codable, Equatable, Sendable {
    static let maxRecentColors = 6

    var size: CGSize
    var strokes: [Stroke]
    var activeColor: CodableColor
    var recentColors: [CodableColor]

    init(size: CGSize = CGSize(width: 1024, height: 1366)) {
        self.size = size
        self.strokes = []
        self.activeColor = .black
        self.recentColors = []
    }

    private enum CodingKeys: String, CodingKey {
        case size, strokes, activeColor, recentColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        size = try container.decode(CGSize.self, forKey: .size)
        strokes = try container.decode([Stroke].self, forKey: .strokes)
        activeColor = try container.decodeIfPresent(CodableColor.self, forKey: .activeColor) ?? .black
        recentColors = try container.decodeIfPresent([CodableColor].self, forKey: .recentColors) ?? []
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

    mutating func pushRecentColor(_ color: CodableColor) {
        recentColors.removeAll { $0 == color }
        recentColors.insert(color, at: 0)
        if recentColors.count > Self.maxRecentColors {
            recentColors = Array(recentColors.prefix(Self.maxRecentColors))
        }
    }
}
