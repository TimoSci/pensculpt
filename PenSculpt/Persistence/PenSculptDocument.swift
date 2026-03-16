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
    @Published var drawingData: Data = Data()
    @Published var sculptObjects: [SculptObject] = []

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

        if let drawingWrapper = wrapper["drawing.pkdrawing"],
           let data = drawingWrapper.regularFileContents {
            self.drawingData = data
        }

        if let sculptDir = wrapper["sculpt_objects"],
           let sculptWrappers = sculptDir.fileWrappers {
            let decoder = JSONDecoder()
            self.sculptObjects = sculptWrappers.values.compactMap { fw in
                fw.regularFileContents.flatMap { try? decoder.decode(SculptObject.self, from: $0) }
            }
        }
    }

    struct Snapshot {
        let strokes: Data
        let metadata: Data
        let drawing: Data
        let sculptObjects: [(id: UUID, data: Data)]
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        let encoder = JSONEncoder()
        let strokesData = try encoder.encode(canvas.strokes)
        let meta = DocumentMetadata(
            createdAt: Date(),
            canvasWidth: canvas.size.width,
            canvasHeight: canvas.size.height
        )
        let metaData = try encoder.encode(meta)
        let sculptData = try sculptObjects.map { obj in
            (id: obj.id, data: try encoder.encode(obj))
        }
        return Snapshot(strokes: strokesData, metadata: metaData, drawing: drawingData, sculptObjects: sculptData)
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

        if !snapshot.drawing.isEmpty {
            directory.addRegularFile(
                withContents: snapshot.drawing,
                preferredFilename: "drawing.pkdrawing"
            )
        }

        let sculptDir = FileWrapper(directoryWithFileWrappers: [:])
        sculptDir.preferredFilename = "sculpt_objects"
        for (id, data) in snapshot.sculptObjects {
            let fw = FileWrapper(regularFileWithContents: data)
            fw.preferredFilename = "\(id.uuidString).json"
            sculptDir.addFileWrapper(fw)
        }
        directory.addFileWrapper(sculptDir)

        return directory
    }
}
