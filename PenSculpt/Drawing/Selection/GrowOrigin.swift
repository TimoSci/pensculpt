import Foundation

/// Where a grow-selection begins.
/// `.stroke` — user tapped on top of an existing stroke; that stroke seeds the selection.
/// `.point` — user tapped on empty canvas; a virtual sphere expands from `anchor`.
enum GrowOrigin: Equatable {
    case stroke(strokeID: UUID, anchor: CGPoint)
    case point(CGPoint)

    var anchor: CGPoint {
        switch self {
        case .stroke(_, let anchor): return anchor
        case .point(let p):          return p
        }
    }

    var initialStrokeID: UUID? {
        switch self {
        case .stroke(let id, _): return id
        case .point:             return nil
        }
    }
}
