import Foundation

enum PrimitiveFitter {

    /// Classifies a skeleton segment as a geometric primitive based on its radius profile.
    static func fit(_ segment: SkeletonSegment) -> FittedPrimitive {
        let radii = segment.points.map { Float($0.radius) }
        guard radii.count >= 2 else {
            let r = radii.first ?? 1
            return FittedPrimitive(type: .cylinder(radius: r), segment: segment)
        }

        let mean = radii.reduce(0, +) / Float(radii.count)
        let variance = radii.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(radii.count)
        let coeffOfVariation = mean > 0 ? sqrt(variance) / mean : 0

        // Check for cylinder: low variation in radius
        if coeffOfVariation < 0.15 {
            return FittedPrimitive(type: .cylinder(radius: mean), segment: segment)
        }

        // Check for cone/taper: strong linear trend
        let slope = linearSlope(radii)
        let linearFitError = linearFitResidual(radii, slope: slope)
        if linearFitError < 0.2 {
            return FittedPrimitive(
                type: .cone(startRadius: radii.first!, endRadius: radii.last!),
                segment: segment
            )
        }

        // Check for sphere: symmetric, peaks in the middle
        if isSymmetricPeak(radii) {
            let maxRadius = radii.max() ?? mean
            return FittedPrimitive(type: .sphere(radius: maxRadius), segment: segment)
        }

        return FittedPrimitive(type: .custom, segment: segment)
    }

    // MARK: - Analysis helpers

    /// Slope of the best-fit line through the radius values (normalized to [0,1] x-axis).
    static func linearSlope(_ values: [Float]) -> Float {
        guard values.count >= 2 else { return 0 }
        let n = Float(values.count)
        let xs = (0..<values.count).map { Float($0) / (n - 1) }
        let xMean = xs.reduce(0, +) / n
        let yMean = values.reduce(0, +) / n
        var num: Float = 0, den: Float = 0
        for i in 0..<values.count {
            num += (xs[i] - xMean) * (values[i] - yMean)
            den += (xs[i] - xMean) * (xs[i] - xMean)
        }
        return den > 0 ? num / den : 0
    }

    /// Normalized residual of a linear fit (0 = perfect line, 1 = poor fit).
    static func linearFitResidual(_ values: [Float], slope: Float) -> Float {
        guard values.count >= 2 else { return 0 }
        let n = Float(values.count)
        let yMean = values.reduce(0, +) / n
        let intercept = yMean - slope * 0.5 // midpoint of normalized x

        var ssRes: Float = 0, ssTot: Float = 0
        for i in 0..<values.count {
            let x = Float(i) / (n - 1)
            let predicted = intercept + slope * x
            ssRes += (values[i] - predicted) * (values[i] - predicted)
            ssTot += (values[i] - yMean) * (values[i] - yMean)
        }
        return ssTot > 0 ? ssRes / ssTot : 0
    }

    /// Checks if the profile is symmetric and peaks near the center.
    static func isSymmetricPeak(_ values: [Float]) -> Bool {
        guard values.count >= 3 else { return false }
        guard let maxIdx = values.indices.max(by: { values[$0] < values[$1] }) else { return false }

        // Peak should be near the center (within 30% of midpoint)
        let mid = Float(values.count - 1) / 2
        let peakOffset = abs(Float(maxIdx) - mid) / mid
        guard peakOffset < 0.3 else { return false }

        // Check symmetry: compare first half with reversed second half
        let half = values.count / 2
        var asymmetry: Float = 0
        for i in 0..<half {
            let mirror = values.count - 1 - i
            let mean = (values[i] + values[mirror]) / 2
            if mean > 0 {
                asymmetry += abs(values[i] - values[mirror]) / mean
            }
        }
        asymmetry /= Float(half)
        return asymmetry < 0.4
    }
}
