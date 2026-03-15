import Foundation

struct SkeletonPoint: Equatable, Sendable {
    let position: CGPoint
    let radius: CGFloat
}

struct Skeleton: Equatable, Sendable {
    let points: [SkeletonPoint]
    let axis: CGVector

    var isEmpty: Bool { points.isEmpty }
}

struct SkeletonSegment: Equatable, Sendable {
    let points: [SkeletonPoint]

    var isEmpty: Bool { points.isEmpty }
}
