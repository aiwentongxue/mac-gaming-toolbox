import Foundation

/// A versioned sharing envelope keeps mouse-only combined macros distinguishable.
enum SharedMacro: Sendable {
    case mouse(MouseMacro)
    case combined(CombinedMacro)

    var name: String {
        switch self {
        case .mouse(let macro): macro.name
        case .combined(let macro): macro.name
        }
    }

    func importedCopy() -> Self {
        switch self {
        case .mouse(var macro):
            macro.id = UUID()
            macro.createdAt = .now
            macro.updatedAt = .now
            return .mouse(macro)
        case .combined(var macro):
            macro.id = UUID()
            macro.createdAt = .now
            macro.updatedAt = .now
            return .combined(macro)
        }
    }
}
enum MacroExchangeError: LocalizedError {
    case invalidFile, unsupportedVersion, tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidFile: cf("sharing.error.invalid")
        case .unsupportedVersion: cf("sharing.error.version")
        case .tooLarge: cf("sharing.error.size")
        }
    }
}

enum MacroExchange {
    static let maximumFileSize = 20 * 1_024 * 1_024

    private struct Envelope: Codable {
        var format = "ClickFlow Macro"
        var version = 1
        var kind: String
        var mouseMacro: MouseMacro?
        var combinedMacro: CombinedMacro?
    }

    static func encode(_ macro: SharedMacro) throws -> Data {
        try validate(macro)
        let envelope: Envelope
        switch macro {
        case .mouse(let value): envelope = Envelope(kind: "mouse", mouseMacro: value)
        case .combined(let value): envelope = Envelope(kind: "combined", combinedMacro: value)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(envelope)
        guard data.count <= maximumFileSize else { throw MacroExchangeError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> SharedMacro {
        guard data.count <= maximumFileSize else { throw MacroExchangeError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope: Envelope
        do { envelope = try decoder.decode(Envelope.self, from: data) }
        catch { throw MacroExchangeError.invalidFile }
        guard envelope.format == "ClickFlow Macro" else { throw MacroExchangeError.invalidFile }
        guard envelope.version == 1 else { throw MacroExchangeError.unsupportedVersion }
        let macro: SharedMacro
        switch envelope.kind {
        case "mouse":
            guard let value = envelope.mouseMacro, envelope.combinedMacro == nil else {
                throw MacroExchangeError.invalidFile
            }
            macro = .mouse(value)
        case "combined":
            guard let value = envelope.combinedMacro, envelope.mouseMacro == nil else {
                throw MacroExchangeError.invalidFile
            }
            macro = .combined(value)
        default: throw MacroExchangeError.invalidFile
        }
        try validate(macro)
        return macro
    }

    static func read(from url: URL) throws -> SharedMacro {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFileSize + 1) ?? Data()
        return try decode(data).importedCopy()
    }

    static func validate(_ shared: SharedMacro) throws {
        switch shared {
        case .mouse(let macro):
            guard macro.schemaVersion == MouseMacro.schemaVersion else { throw MacroExchangeError.unsupportedVersion }
            try validateSettings(count: macro.repeatCount, delay: macro.repeatDelayMilliseconds, speed: macro.playbackSpeed)
            try validateTimeline(macro.events.map(\.timestampMilliseconds), ids: macro.events.map(\.id))
            for event in macro.events {
                try validatePosition(event.position)
                if event.kind == .mouseDown || event.kind == .mouseUp {
                    guard event.button != nil else { throw MacroExchangeError.invalidFile }
                }
            }
        case .combined(let macro):
            guard macro.schemaVersion == CombinedMacro.schemaVersion else { throw MacroExchangeError.unsupportedVersion }
            try validateSettings(count: macro.repeatCount, delay: macro.repeatDelayMilliseconds, speed: macro.playbackSpeed)
            try validateTimeline(macro.events.map(\.timestampMilliseconds), ids: macro.events.map(\.id))
            for event in macro.events {
                try validatePosition(event.position)
                if event.kind == .mouseDown || event.kind == .mouseUp {
                    guard event.button != nil else { throw MacroExchangeError.invalidFile }
                }
                if event.kind == .keyDown || event.kind == .keyUp {
                    guard event.keyCode != nil else { throw MacroExchangeError.invalidFile }
                }
                if let value = event.controlValue, !value.isFinite { throw MacroExchangeError.invalidFile }
            }
        }
    }

    private static func validateSettings(count: Int, delay: Double, speed: Double) throws {
        guard count >= 1, validTime(delay), speed.isFinite, (0.25...4).contains(speed) else {
            throw MacroExchangeError.invalidFile
        }
    }

    private static func validTime(_ value: Double) -> Bool {
        // Leave headroom for 0.25x playback before converting to Int64 nanoseconds.
        value.isFinite && value >= 0 && value <= 1_000_000_000_000
    }

    private static func validateTimeline(_ times: [Double], ids: [UUID]) throws {
        guard Set(ids).count == ids.count else { throw MacroExchangeError.invalidFile }
        var previous = 0.0
        for time in times {
            guard validTime(time), time >= previous else { throw MacroExchangeError.invalidFile }
            previous = time
        }
    }

    private static func validatePosition(_ point: ScreenPoint?) throws {
        if let point, !point.x.isFinite || !point.y.isFinite { throw MacroExchangeError.invalidFile }
    }
}
