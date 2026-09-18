@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing
import UniformTypeIdentifiers

@MainActor
struct ChecklistShareTests {
    private func makeDocument(names: [String]) throws -> ChecklistExportDocument {
        let checklists = names.map { Checklist(name: $0, items: [ChecklistItem(title: "Milk")]) }
        return try ChecklistExportDocument(checklists: checklists)
    }

    @Test
    func itemProviderAdvertisesJSONTypeAndSuggestedName() throws {
        let document = try makeDocument(names: ["Groceries"])
        let filename = ChecklistExport.filename() + ".json"

        let provider = ChecklistShare.itemProvider(for: document, filename: filename)

        #expect(provider.suggestedName == filename)
        #expect(provider.registeredTypeIdentifiers.contains(UTType.json.identifier))
    }

    @Test
    func itemProviderYieldsTheDocumentBytes() async throws {
        let document = try makeDocument(names: ["Groceries", "Packing"])

        let provider = ChecklistShare.itemProvider(for: document, filename: "x.json")
        let data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.coderReadCorrupt))
                }
            }
        }

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            Issue.record("provider bytes did not classify as loaded")
            return
        }
        #expect(envelope.checklists.map(\.name) == ["Groceries", "Packing"])
        #expect(envelope.deviceID == "")
        #expect(envelope.tombstones.isEmpty)
    }

    @Test
    func emptyDocumentStillYieldsValidJSONBytes() async throws {
        let document = try ChecklistExportDocument(checklists: [])
        let provider = ChecklistShare.itemProvider(for: document, filename: "x.json")

        let data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.json.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.coderReadCorrupt)) }
            }
        }

        guard case .loaded(let envelope) = ChecklistCodec.classify(data) else {
            Issue.record("empty document bytes did not classify as loaded")
            return
        }
        #expect(envelope.checklists.isEmpty)
    }
}