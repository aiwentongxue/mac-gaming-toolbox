import Combine
import Foundation
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif

enum SidebarSection: String, CaseIterable, Identifiable {
    case gaming
    case storage
    case clickFlow
    case appDrop
    case information

    var id: String { rawValue }

    var items: [SidebarItem] {
        SidebarItem.allCases.filter { $0.section == self }
    }

    var localizedTitle: String {
        switch self {
        case .gaming:
            tr("游戏运行与增强", "Gaming & Performance")
        case .storage:
            tr("存储与系统维护", "Storage & Maintenance")
        case .clickFlow:
            "ClickFlow"
        case .appDrop:
            "AppDrop"
        case .information:
            tr("帮助与个性化", "Help & Personalization")
        }
    }

}

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case metalHUD
    case hoYoAssistant
    case processPriority
    case steamDeckSpoof
    case diskManager
    case systemCleaner
    case cfClicker
    case cfMacros
    case cfCombinedMacros
    case cfSettings
    case appDrop
    case appearanceWallpaper
    case tutorials
    case changelogAbout

    static let storageKey = "app.selectedSidebarItem"
    static let legacyStorageKey = "mainSelectedSection"

    var id: String { rawValue }

    var section: SidebarSection {
        switch self {
        case .metalHUD, .hoYoAssistant, .processPriority, .steamDeckSpoof:
            .gaming
        case .diskManager, .systemCleaner:
            .storage
        case .cfClicker, .cfMacros, .cfCombinedMacros, .cfSettings:
            .clickFlow
        case .appDrop:
            .appDrop
        case .appearanceWallpaper, .tutorials, .changelogAbout:
            .information
        }
    }

    var iconName: String {
        switch self {
        case .metalHUD: "gauge.with.dots.needle.67percent"
        case .hoYoAssistant: "gamecontroller.fill"
        case .processPriority: "bolt.fill"
        case .steamDeckSpoof: "rectangle.2.swap"
        case .diskManager: "externaldrive.fill"
        case .systemCleaner: "trash.fill"
        case .cfClicker: "cursorarrow.click.2"
        case .cfMacros: "record.circle"
        case .cfCombinedMacros: "keyboard.badge.ellipsis"
        case .cfSettings: "gearshape"
        case .appDrop: "arrow.down.app.fill"
        case .appearanceWallpaper: "photo.fill.on.rectangle.fill"
        case .tutorials: "book.pages.fill"
        case .changelogAbout: "info.circle"
        }
    }

    var localizedTitle: String {
        switch self {
        case .metalHUD:
            "MetalHUD"
        case .hoYoAssistant:
            tr("HoYoGames 启动帮助", "HoYoGames Launch Assistant")
        case .processPriority:
            tr("进程优化", "Process Optimization")
        case .steamDeckSpoof:
            tr("SteamDeck 模式", "SteamDeck Mode")
        case .diskManager:
            tr("磁盘挂载管理", "Volume Mounting")
        case .systemCleaner:
            tr("缓存与日志清理", "Cache & Log Cleanup")
        case .cfClicker:
            tr("自动连点器", "Auto Clicker")
        case .cfMacros:
            tr("鼠标宏", "Mouse Macros")
        case .cfCombinedMacros:
            tr("组合宏", "Combined Macros")
        case .cfSettings:
            tr("ClickFlow 设置", "ClickFlow Settings")
        case .appDrop:
            "AppDrop"
        case .appearanceWallpaper:
            tr("外观与壁纸", "Appearance & Wallpaper")
        case .tutorials:
            tr("游戏教程", "Tutorials")
        case .changelogAbout:
            tr("更新日志与关于", "Changelog & About")
        }
    }

    var sidebarTitle: String {
        switch self {
        case .metalHUD:
            "MetalHUD"
        case .hoYoAssistant:
            "HoYoGames"
        case .processPriority:
            tr("进程优化", "Process Boost")
        case .steamDeckSpoof:
            "SteamDeck"
        case .diskManager:
            tr("磁盘挂载", "Volumes")
        case .systemCleaner:
            tr("缓存清理", "Cleanup")
        case .cfClicker:
            tr("自动连点", "Auto Clicker")
        case .cfMacros:
            tr("鼠标宏", "Mouse Macros")
        case .cfCombinedMacros:
            tr("组合宏", "Combined Macros")
        case .cfSettings:
            tr("设置", "Settings")
        case .appDrop:
            "AppDrop"
        case .appearanceWallpaper:
            tr("外观壁纸", "Appearance")
        case .tutorials:
            tr("游戏教程", "Tutorials")
        case .changelogAbout:
            tr("关于与日志", "About & Log")
        }
    }

    var isClickFlowPage: Bool {
        section == .clickFlow
    }

    var clickFlowPage: ClickFlowIntegratedPage? {
        switch self {
        case .cfClicker: .clicker
        case .cfMacros: .macros
        case .cfCombinedMacros: .combinedMacros
        case .cfSettings: .settings
        default: nil
        }
    }
}

@MainActor
final class NavigationModel: ObservableObject {
    @Published var selection: SidebarItem {
        didSet {
            guard oldValue != selection else { return }
            defaults.set(selection.rawValue, forKey: SidebarItem.storageKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = Self.persistedSelection(in: defaults)
    }

    func select(_ item: SidebarItem) {
        selection = item
    }

    static func persistedSelection(in defaults: UserDefaults) -> SidebarItem {
        if let stored = defaults.string(forKey: SidebarItem.storageKey),
           let item = SidebarItem(rawValue: stored) {
            return item
        }

        let migrated: SidebarItem
        switch defaults.string(forKey: SidebarItem.legacyStorageKey) {
        case "clickFlow":
            migrated = .cfClicker
        case "toolbox":
            migrated = .metalHUD
        default:
            migrated = .metalHUD
        }
        defaults.set(migrated.rawValue, forKey: SidebarItem.storageKey)
        return migrated
    }
}
