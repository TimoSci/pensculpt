import Foundation

struct SculptConfig: Codable, Equatable, Sendable {
    /// Minimum curvature radius in points. Controls how smooth surface transitions are.
    /// Higher values produce smoother shapes. Lower values allow sharper features.
    var minCurvatureRadius: CGFloat = 25

    static let `default` = SculptConfig()
}
