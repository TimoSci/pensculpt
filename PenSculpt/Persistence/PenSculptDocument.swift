import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pensculpt = UTType(exportedAs: "com.pensculpt.document")
}

final class PenSculptDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.pensculpt] }
    static var writableContentTypes: [UTType] { [.pensculpt] }

    @Published var canvas: Canvas

    init() {
        self.canvas = Canvas()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.canvas = try JSONDecoder().decode(Canvas.self, from: data)
    }

    func snapshot(contentType: UTType) throws -> Data {
        try JSONEncoder().encode(canvas)
    }

    func fileWrapper(snapshot: Data, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: snapshot)
    }
}
