import SwiftUI

struct LassoOverlay: View {
    @Binding var lassoPoints: [CGPoint]
    var onLassoCompleted: ([CGPoint]) -> Void
    @State private var isClosed = false

    var body: some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if isClosed {
                                lassoPoints = []
                                isClosed = false
                            }
                            if lassoPoints.isEmpty {
                                lassoPoints = [value.location]
                            } else {
                                lassoPoints.append(value.location)
                            }
                        }
                        .onEnded { _ in
                            if lassoPoints.count > 2 {
                                lassoPoints.append(lassoPoints[0])
                                isClosed = true
                                onLassoCompleted(lassoPoints)
                            } else {
                                lassoPoints = []
                            }
                        }
                )

            LassoShape(points: lassoPoints)
                .stroke(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                .allowsHitTesting(false)
        }
    }
}

struct LassoShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
