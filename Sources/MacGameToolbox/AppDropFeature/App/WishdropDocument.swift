import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let wishdrop = UTType(exportedAs: "com.appdrop.wishdrop")
}

/// File wrapper used by `.fileExporter` / `.fileImporter`.
struct WishdropDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.wishdrop] }
    static var writableContentTypes: [UTType] { [.wishdrop] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
