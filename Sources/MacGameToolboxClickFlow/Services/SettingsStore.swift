import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let clickerConfiguration = "clickerConfiguration"
        static let hotkeys = "hotkeys"
        static let hotkeySchemaVersion = "hotkeySchemaVersion"
        static let selectedPage = "selectedPage"
        static let recentMacroID = "recentMacroID"
        static let recentCombinedMacroID = "recentCombinedMacroID"
        static let mouseRecordingMode = "mouseRecordingMode"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var hotkeys: [HotkeyAction: HotkeyConfiguration]
    private(set) var recentMacroID: UUID?
    private(set) var recentCombinedMacroID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.integer(forKey: Key.hotkeySchemaVersion) < 2 {
            hotkeys = HotkeyConfiguration.defaults
            defaults.removeObject(forKey: Key.hotkeys)
            defaults.set(2, forKey: Key.hotkeySchemaVersion)
        } else if let data = defaults.data(forKey: Key.hotkeys),
           let decoded = try? decoder.decode([HotkeyAction: HotkeyConfiguration].self, from: data) {
            hotkeys = decoded
        } else {
            hotkeys = HotkeyConfiguration.defaults
        }
        recentMacroID = defaults.string(forKey: Key.recentMacroID).flatMap(UUID.init(uuidString:))
        recentCombinedMacroID = defaults.string(forKey: Key.recentCombinedMacroID).flatMap(UUID.init(uuidString:))
    }

    func loadClickerConfiguration() -> ClickerConfiguration {
        guard let data = defaults.data(forKey: Key.clickerConfiguration),
              let configuration = try? decoder.decode(ClickerConfiguration.self, from: data) else {
            return ClickerConfiguration()
        }
        return configuration.sanitizedForExecution()
    }

    func saveClickerConfiguration(_ configuration: ClickerConfiguration) {
        defaults.set(try? encoder.encode(configuration), forKey: Key.clickerConfiguration)
    }

    func loadSelectedPage() -> SidebarPage {
        guard let rawValue = defaults.string(forKey: Key.selectedPage),
              let page = SidebarPage(rawValue: rawValue) else {
            return .clicker
        }
        return page
    }

    func saveSelectedPage(_ page: SidebarPage) {
        defaults.set(page.rawValue, forKey: Key.selectedPage)
    }

    func saveHotkeys(_ configurations: [HotkeyAction: HotkeyConfiguration]) {
        hotkeys = configurations
        defaults.set(try? encoder.encode(configurations), forKey: Key.hotkeys)
        defaults.set(2, forKey: Key.hotkeySchemaVersion)
    }

    func setRecentMacroID(_ id: UUID?) {
        recentMacroID = id
        defaults.set(id?.uuidString, forKey: Key.recentMacroID)
    }

    func loadMouseRecordingMode() -> MouseRecordingMode {
        defaults.string(forKey: Key.mouseRecordingMode)
            .flatMap(MouseRecordingMode.init(rawValue:)) ?? .fullMotion
    }

    func saveMouseRecordingMode(_ mode: MouseRecordingMode) {
        defaults.set(mode.rawValue, forKey: Key.mouseRecordingMode)
    }

    func setRecentCombinedMacroID(_ id: UUID?) {
        recentCombinedMacroID = id
        defaults.set(id?.uuidString, forKey: Key.recentCombinedMacroID)
    }
}
