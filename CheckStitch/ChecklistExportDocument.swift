import CheckStitchCore
import SwiftUI
import UniformTypeIdentifiers

/// In-memory export document: the codec-encoded envelope bytes plus a JSON content
/// type. Reading only satisfies the protocol — the app never opens a document this
/// way (import goes through `.fileImporter`).
struct ChecklistExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(checklists: [Checklist]) throws {
        self.data = try ChecklistExport.data(checklists: checklists)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}