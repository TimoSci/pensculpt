import Foundation

struct CodableColor: Codable, Equatable, Sendable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
}

struct Stroke: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var points: [StrokePoint]
    var color: CodableColor
    let boundingBox: CGRect

    private enum CodingKeys: String, CodingKey {
        case id, points, color
    }

    init(id: UUID = UUID(), points: [StrokePoint], color: CodableColor = .black) {
        self.id = id
        self.points = points
        self.color = color
        self.boundingBox = Self.computeBoundingBox(points)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        points = try container.decode([StrokePoint].self, forKey: .points)
        color = try container.decode(CodableColor.self, forKey: .color)
        boundingBox = Self.computeBoundingBox(points)
    }

    private static func computeBoundingBox(_ points: [StrokePoint]) -> CGRect {
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
