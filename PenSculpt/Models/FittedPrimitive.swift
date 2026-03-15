import Foundation

enum PrimitiveType: Equatable, Sendable {
    case cylinder(radius: Float)
    case cone(startRadius: Float, endRadius: Float)
    case sphere(radius: Float)
    case custom
}

struct FittedPrimitive: Equatable, Sendable {
    let type: PrimitiveType
    let segment: SkeletonSegment
}
