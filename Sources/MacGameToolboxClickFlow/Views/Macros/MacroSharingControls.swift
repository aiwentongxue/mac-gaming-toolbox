import SwiftUI
import UniformTypeIdentifiers

struct MacroShareDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(macro: SharedMacro) throws { data = try MacroExchange.encode(macro) }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw MacroExchangeError.invalidFile }
        _ = try MacroExchange.decode(data)
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
struct MacroSharingControls: ToolbarContent {
    @EnvironmentObject private var appState: AppState
    let macro: SharedMacro?
    @State private var importing = false
    @State private var exporting = false
    @State private var document: MacroShareDocument?
    @State private var filename = "Macro"

    private var isBusy: Bool {
        appState.isRecording || appState.isRecordingCombinedMacro || appState.isImportingMacro
    }

    var body: some ToolbarContent {
        ToolbarItem {
            Button(cf("sharing.import"), systemImage: "square.and.arrow.down") { importing = true }
                .help(cf("sharing.import"))
                .accessibilityIdentifier("macro.import")
                .disabled(isBusy)
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    switch result {
                    case .success(let url): appState.importMacro(from: url)
                    case .failure(let error): appState.userMessage = error.localizedDescription
                    }
                }
        }
        ToolbarItem {
            Button(cf("sharing.export"), systemImage: "square.and.arrow.up") {
                guard let macro else { return }
                do {
                    document = try MacroShareDocument(macro: macro)
                    filename = macro.name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
                    if filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { filename = "Macro" }
                    exporting = true
                } catch { appState.userMessage = error.localizedDescription }
            }
            .help(cf("sharing.export"))
            .accessibilityIdentifier("macro.export")
            .disabled(macro == nil || isBusy)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: filename) { result in
                if case .failure(let error) = result { appState.userMessage = error.localizedDescription }
            }
        }
    }
}
