import Foundation

enum DensityProbe {
    /// Smallest extra radius needed to admit at least one new stroke.
    /// Returns `nil` when there are no candidates. Returns `0` when at least one
    /// candidate is already within `currentRadius` of the frontier (clamped).
    static func minimumDeltaR(
        currentRadius: CGFloat,
        frontier: [CGPoint],
        candidates: [Stroke]
    ) -> CGFloat? {
        guard !candidates.isEmpty else { return nil }

        var bestDistance = CGFloat.infinity
        for candidate in candidates {
            for sp in candidate.points {
                for fp in frontier {
                    let d = hypot(sp.location.x - fp.x, sp.location.y - fp.y)
                    if d < bestDistance { bestDistance = d }
                }
            }
        }

        return max(0, bestDistance - currentRadius)
    }
}
