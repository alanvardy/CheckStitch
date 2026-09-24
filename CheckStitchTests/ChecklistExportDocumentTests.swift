@testable import CheckStitch
import Testing
import UniformTypeIdentifiers

struct ChecklistExportDocumentTests {
    @Test
    func readableContentTypesIsJSONOnly() {
        // The export panel derives the `.json` extension from this; widening it
        // would silently change what the share sheet/import accept.
        #expect(ChecklistExportDocument.readableContentTypes == [.json])
    }
}