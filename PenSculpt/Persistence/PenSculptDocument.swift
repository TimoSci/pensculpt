import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pensculpt = UTType(exportedAs: "com.pensculpt.document")
}

struct DocumentMetadata: Codable {
    var version: Int = 1
    var createdAt: Date
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat
}

final class PenSculptDocument: ReferenceFileDocument, ObservableObject {
    static var readableContentTypes: [UTType] { [.pensculpt] }
    static var writableContentTypes: [UTType] { [.pensculpt] }

    @Published var canvas: Canvas

    init() {
        self.canvas = Canvas()
    }

    required init(configuration: ReadConfiguration) throws {
        guard let wrapper = configuration.file.fileWrappers else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Read strokes
        guard let strokesWrapper = wrapper["strokes.json"],
              let strokesData = strokesWrapper.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let strokes = try JSONDecoder().decode([Stroke].self, from: strokesData)

        // Read metadata for canvas size
        var size = CGSize(width: 1024, height: 1366)
        if let metaWrapper = wrapper["metadata.json"],
           let metaData = metaWrapper.regularFileContents {
            let meta = try JSONDecoder().decode(DocumentMetadata.self, from: metaData)
            size = CGSize(width: meta.canvasWidth, height: meta.canvasHeight)
        }

        self.canvas = Canvas(size: size)
        self.canvas.strokes = strokes
    }

    struct Snapshot {
        let strokes: Data
        let metadata: Data
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        let strokesData = try JSONEncoder().encode(canvas.strokes)
        let meta = DocumentMetadata(
            createdAt: Date(),
            canvasWidth: canvas.size.width,
            canvasHeight: canvas.size.height
        )
        let metaData = try JSONEncoder().encode(meta)
        return Snapshot(strokes: strokesData, metadata: metaData)
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        let directory = FileWrapper(directoryWithFileWrappers: [:])

        directory.addRegularFile(
            withContents: snapshot.strokes,
            preferredFilename: "strokes.json"
        )
        directory.addRegularFile(
            withContents: snapshot.metadata,
            preferredFilename: "metadata.json"
        )

        // Placeholder for sculpt_objects/ — Stage 2 will populate this
        let sculptDir = FileWrapper(directoryWithFileWrappers: [:])
        sculptDir.preferredFilename = "sculpt_objects"
        directory.addFileWrapper(sculptDir)

        return directory
    }
}
