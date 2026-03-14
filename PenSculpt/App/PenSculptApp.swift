import SwiftUI

@main
struct PenSculptApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PenSculptDocument() }) { config in
            DrawingScreen(
                canvas: Binding(
                    get: { config.document.canvas },
                    set: { config.document.canvas = $0 }
                ),
                drawingData: Binding(
                    get: { config.document.drawingData },
                    set: { config.document.drawingData = $0 }
                )
            )
        }
    }
}
