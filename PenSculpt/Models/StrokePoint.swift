import Foundation

struct StrokePoint: Codable, Equatable, Sendable {
    let location: CGPoint
    let pressure: CGFloat
    let tilt: CGFloat
    let azimuth: CGFloat
    let timestamp: TimeInterval
}
