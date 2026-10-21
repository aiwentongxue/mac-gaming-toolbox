@preconcurrency import Carbon
import CoreGraphics
import Foundation

enum RecordingTimeline {
    static func appending(_ newEvents: [MacroEvent], to existing: [MacroEvent]) -> [MacroEvent] {
        let offset = existing.isEmpty ? 0 : (existing.map(\.timestampMilliseconds).max() ?? 0) + 1
        return existing + newEvents.map {
            var event = $0
            event.timestampMilliseconds += offset
            return event
        }
    }

    static func appending(
        _ newEvents: [CombinedMacroEvent],
        to existing: [CombinedMacroEvent]
    ) -> [CombinedMacroEvent] {
        let offset = existing.isEmpty ? 0 : (existing.map(\.timestampMilliseconds).max() ?? 0) + 1
        return existing + newEvents.map {
            var event = $0
            event.timestampMilliseconds += offset
            return event
        }
    }

    static func removingTerminalControlClick(from events: [MacroEvent]) -> [MacroEvent] {
        if let upIndex = events.lastIndex(where: { $0.kind == .mouseUp && $0.button != nil }),
           let button = events[upIndex].button,
           let downIndex = events[..<upIndex].lastIndex(where: {
               $0.kind == .mouseDown && $0.button == button
           }),
           events[upIndex].timestampMilliseconds - events[downIndex].timestampMilliseconds <= 1_500,
           !events[(downIndex + 1)..<upIndex].contains(where: { $0.kind != .mouseMove }),
           !events[(upIndex + 1)...].contains(where: {
               $0.kind == .mouseDown || $0.kind == .mouseUp || $0.kind == .scroll
           }) {
            var result = events
            result.remove(at: upIndex)
            result.remove(at: downIndex)
            return result
        }
        guard let downIndex = events.lastIndex(where: { $0.kind == .mouseDown && $0.button != nil }),
              !events[(downIndex + 1)...].contains(where: {
                  $0.kind == .mouseDown || $0.kind == .mouseUp || $0.kind == .scroll
              }) else { return events }
        var result = events
        result.remove(at: downIndex)
        return result
    }

    static func removingTerminalControlClick(
        from events: [CombinedMacroEvent]
    ) -> [CombinedMacroEvent] {
        if let upIndex = events.lastIndex(where: { $0.kind == .mouseUp && $0.button != nil }),
           let button = events[upIndex].button,
           let downIndex = events[..<upIndex].lastIndex(where: {
               $0.kind == .mouseDown && $0.button == button
           }),
           events[upIndex].timestampMilliseconds - events[downIndex].timestampMilliseconds <= 1_500,
           !events[(downIndex + 1)..<upIndex].contains(where: { $0.kind != .mouseMove }),
           !events[(upIndex + 1)...].contains(where: {
               $0.kind == .mouseDown || $0.kind == .mouseUp || $0.kind == .scroll ||
                   $0.kind == .keyDown || $0.kind == .keyUp
           }) {
            var result = events
            result.remove(at: upIndex)
            result.remove(at: downIndex)
            return result
        }
        guard let downIndex = events.lastIndex(where: { $0.kind == .mouseDown && $0.button != nil }),
              !events[(downIndex + 1)...].contains(where: {
                  $0.kind == .mouseDown || $0.kind == .mouseUp || $0.kind == .scroll ||
                      $0.kind == .keyDown || $0.kind == .keyUp
              }) else { return events }
        var result = events
        result.remove(at: downIndex)
        return result
    }

    static func removingTerminalHotkey(
        from events: [CombinedMacroEvent],
        configuration: HotkeyConfiguration
    ) -> [CombinedMacroEvent] {
        let primaryKeyCode = UInt16(clamping: configuration.keyCode)
        guard let primaryDownIndex = events.lastIndex(where: {
            $0.kind == .keyDown && $0.keyCode == primaryKeyCode
        }), terminalKeyEventIsHotkey(events[primaryDownIndex], configuration: configuration) else {
            return events
        }

        let allowedModifierKeyCodes = modifierKeyCodes(for: configuration.modifiers)
        let lastKeyboardIndex = events.lastIndex(where: { $0.kind == .keyDown || $0.kind == .keyUp })
        guard let lastKeyboardIndex,
              !events[(primaryDownIndex + 1)...].contains(where: {
                  guard $0.kind == .keyDown || $0.kind == .keyUp else { return false }
                  return $0.keyCode != primaryKeyCode
                      && !allowedModifierKeyCodes.contains($0.keyCode ?? UInt16.max)
              }) else {
            return events
        }

        var indicesToRemove = Set<Int>()
        for index in primaryDownIndex...lastKeyboardIndex {
            let event = events[index]
            if event.kind == .keyDown || event.kind == .keyUp {
                if event.keyCode == primaryKeyCode ||
                    allowedModifierKeyCodes.contains(event.keyCode ?? UInt16.max) {
                    indicesToRemove.insert(index)
                }
            }
        }

        var remainingModifierGroups = modifierKeyGroups(for: configuration.modifiers)
        var index = primaryDownIndex
        while index > events.startIndex, !remainingModifierGroups.isEmpty {
            index -= 1
            let event = events[index]
            guard event.kind == .keyDown || event.kind == .keyUp else { continue }
            guard let keyCode = event.keyCode,
                  let groupIndex = remainingModifierGroups.firstIndex(where: { $0.contains(keyCode) }),
                  event.kind == .keyDown else { break }
            indicesToRemove.insert(index)
            remainingModifierGroups.remove(at: groupIndex)
        }

        return events.enumerated().compactMap { index, event in
            indicesToRemove.contains(index) ? nil : event
        }
    }

    private static func terminalKeyEventIsHotkey(
        _ event: CombinedMacroEvent,
        configuration: HotkeyConfiguration
    ) -> Bool {
        guard let rawModifiers = event.keyboardModifiers else {
            return configuration.modifiers == 0
        }
        let flags = CGEventFlags(rawValue: rawModifiers)
        let expected: [(UInt32, CGEventFlags)] = [
            (UInt32(cmdKey), .maskCommand),
            (UInt32(optionKey), .maskAlternate),
            (UInt32(controlKey), .maskControl),
            (UInt32(shiftKey), .maskShift)
        ]
        return expected.allSatisfy { carbonModifier, eventFlag in
            configuration.modifiers & carbonModifier == 0 || flags.contains(eventFlag)
        }
    }

    private static func modifierKeyCodes(for modifiers: UInt32) -> Set<UInt16> {
        modifierKeyGroups(for: modifiers).reduce(into: Set<UInt16>()) {
            $0.formUnion($1)
        }
    }

    private static func modifierKeyGroups(for modifiers: UInt32) -> [Set<UInt16>] {
        var result: [Set<UInt16>] = []
        if modifiers & UInt32(cmdKey) != 0 { result.append([54, 55]) }
        if modifiers & UInt32(shiftKey) != 0 { result.append([56, 60]) }
        if modifiers & UInt32(optionKey) != 0 { result.append([58, 61]) }
        if modifiers & UInt32(controlKey) != 0 { result.append([59, 62]) }
        return result
    }
}
