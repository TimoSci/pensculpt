import Foundation

/// Marker protocol for selection strategies. Each conforming type defines
/// its own input shape; consumers call concrete static APIs directly.
/// The protocol exists to document the family and to anchor future
/// shared APIs (e.g. logging, analytics) without forcing a single signature.
protocol SelectionStrategy {
    associatedtype Input
}
