import Foundation

/// One frame of grow-session state for visualization consumers.
struct GrowFrame {
    let radius: CGFloat
    let center: CGPoint
    let includedStrokeIDs: Set<UUID>
    let nextCandidateID: UUID?
    let isPaused: Bool
}

enum GrowStrategy: SelectionStrategy {
    typealias Input = GrowOrigin

    // MARK: Tunables (iterate during manual testing)
    static let baseGrowthSpeed: CGFloat = 50.0
    static let densityPauseFactor: CGFloat = 0.1
    static let densityPauseThreshold: CGFloat = 3.0
    static let initialRadius: CGFloat = 8.0

    /// Starts a new grow session, immediately admitting any strokes within `initialRadius`
    /// (and the seed stroke itself, if origin is `.stroke`).
    static func start(origin: GrowOrigin, canvas: Canvas) -> GrowSession {
        let session = GrowSession(origin: origin, allStrokes: canvas.strokes)
        session.admitInitial()
        return session
    }
}

/// Mutable per-hold state. Driven by `tick(deltaTime:)` from a display link.
final class GrowSession {
    let origin: GrowOrigin
    let allStrokes: [Stroke]

    private(set) var currentRadius: CGFloat = GrowStrategy.initialRadius
    private(set) var includedStrokeIDs: Set<UUID> = []
    private(set) var nextCandidateID: UUID?
    private(set) var isPaused: Bool = false

    init(origin: GrowOrigin, allStrokes: [Stroke]) {
        self.origin = origin
        self.allStrokes = allStrokes
    }

    /// Admit seed (for stroke origins) and any strokes already within `initialRadius`.
    func admitInitial() {
        if let seedID = origin.initialStrokeID {
            includedStrokeIDs.insert(seedID)
        }
        admitWithinRadius()
        recomputeNextCandidate()
    }

    /// Advances by `deltaTime` seconds. Updates radius (modulated by density), admits
    /// strokes inside the new radius, recomputes the next candidate and pause state.
    @discardableResult
    func tick(deltaTime: TimeInterval) -> GrowFrame {
        let nominalDeltaR = GrowStrategy.baseGrowthSpeed * CGFloat(deltaTime)
        let densityFactor = computeDensityFactor(nominalDeltaR: nominalDeltaR)
        let appliedDeltaR = nominalDeltaR * densityFactor
        currentRadius += appliedDeltaR
        admitWithinRadius()
        recomputeNextCandidate()
        isPaused = densityFactor < 0.5

        return GrowFrame(
            radius: currentRadius,
            center: origin.anchor,
            includedStrokeIDs: includedStrokeIDs,
            nextCandidateID: nextCandidateID,
            isPaused: isPaused
        )
    }

    /// Returns the final selection (snapshot of included strokes). Idempotent.
    func finalize() -> Set<UUID> {
        return includedStrokeIDs
    }

    // MARK: - Internals

    private var frontierPoints: [CGPoint] {
        var pts: [CGPoint] = [origin.anchor]
        for s in allStrokes where includedStrokeIDs.contains(s.id) {
            pts.append(contentsOf: s.points.map { $0.location })
        }
        return pts
    }

    private var candidateStrokes: [Stroke] {
        allStrokes.filter { !includedStrokeIDs.contains($0.id) }
    }

    private func admitWithinRadius() {
        let frontier = frontierPoints
        for stroke in candidateStrokes {
            for sp in stroke.points {
                var minD = CGFloat.infinity
                for fp in frontier {
                    let d = hypot(sp.location.x - fp.x, sp.location.y - fp.y)
                    if d < minD { minD = d }
                }
                if minD <= currentRadius {
                    includedStrokeIDs.insert(stroke.id)
                    break
                }
            }
        }
    }

    private func recomputeNextCandidate() {
        let frontier = frontierPoints
        var bestID: UUID?
        var bestD = CGFloat.infinity
        for stroke in candidateStrokes {
            for sp in stroke.points {
                for fp in frontier {
                    let d = hypot(sp.location.x - fp.x, sp.location.y - fp.y)
                    if d < bestD { bestD = d; bestID = stroke.id }
                }
            }
        }
        nextCandidateID = bestID
    }

    /// 1.0 = full speed; less = slowdown. Pause when next-stroke gap is much
    /// larger than what we'd cross in this tick at full speed. Doesn't pause
    /// before any strokes are admitted — the user is still waiting for the
    /// first inclusion, so the radius needs to grow at full speed to find it.
    private func computeDensityFactor(nominalDeltaR: CGFloat) -> CGFloat {
        guard !includedStrokeIDs.isEmpty else { return 1.0 }
        guard let deltaR = DensityProbe.minimumDeltaR(
            currentRadius: currentRadius,
            frontier: frontierPoints,
            candidates: candidateStrokes
        ), nominalDeltaR > 0 else {
            return 1.0
        }
        let ratio = deltaR / nominalDeltaR
        if ratio > GrowStrategy.densityPauseThreshold {
            return GrowStrategy.densityPauseFactor
        }
        return 1.0
    }
}
