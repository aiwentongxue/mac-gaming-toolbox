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
    case diskManager
    case systemCleaner
    case cfClicker
    case cfMacros
    case cfCombinedMacros
    case cfSettings
    case appDropWishlist
    case appDropTodayDrops
    case appDropHistoricalLows
    case appDropSettings
    case appearanceWallpaper
    case tutorials
    case changelogAbout

    static let storageKey = "app.selectedSidebarItem"
    static let legacyStorageKey = "mainSelectedSection"

    var id: String { rawValue }

    var section: SidebarSection {
        switch self {
        case .metalHUD, .hoYoAssistant, .processPriority:
            .gaming
        case .diskManager, .systemCleaner:
            .storage
        case .cfClicker, .cfMacros, .cfCombinedMacros, .cfSettings:
            .clickFlow
        case .appDropWishlist, .appDropTodayDrops, .appDropHistoricalLows, .appDropSettings:
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
        case .diskManager: "externaldrive.fill"
        case .systemCleaner: "trash.fill"
        case .cfClicker: "cursorarrow.click.2"
        case .cfMacros: "record.circle"
        case .cfCombinedMacros: "keyboard.badge.ellipsis"
        case .cfSettings: "gearshape"
        case .appDropWishlist: "heart"
        case .appDropTodayDrops: "arrow.down.right.circle"
        case .appDropHistoricalLows: "chart.line.downtrend.xyaxis"
        case .appDropSettings: "gearshape"
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
        case .appDropWishlist:
            tr("心愿单", "Wishlist")
        case .appDropTodayDrops:
            tr("今日降价", "Today's Drops")
        case .appDropHistoricalLows:
            tr("历史低价", "Historical Lows")
        case .appDropSettings:
            tr("AppDrop 设置", "AppDrop Settings")
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
        case .appDropWishlist:
            tr("心愿单", "Wishlist")
        case .appDropTodayDrops:
            tr("今日降价", "Today")
        case .appDropHistoricalLows:
            tr("历史低价", "Lowest")
        case .appDropSettings:
            tr("设置", "Settings")
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

    var appDropPage: AppDropPage? {
        switch self {
        case .appDropWishlist: .wishlist
        case .appDropTodayDrops: .todayDrops
        case .appDropHistoricalLows: .historicalLows
        case .appDropSettings: .settings
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

    @Published private(set) var expandedSections: Set<SidebarSection> {
        didSet { persistExpandedSections() }
    }

    private let defaults: UserDefaults
    private static let expandedSectionsKey = "app.expandedSidebarSections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = Self.persistedSelection(in: defaults)
        if let stored = defaults.stringArray(forKey: Self.expandedSectionsKey) {
            expandedSections = Set(stored.compactMap(SidebarSection.init(rawValue:)))
        } else {
            expandedSections = Set(SidebarSection.allCases)
        }
    }

    func select(_ item: SidebarItem) {
        if selection != item {
            selection = item
        }
        expand(item.section)
    }

    func isExpanded(_ section: SidebarSection) -> Bool {
        expandedSections.contains(section)
    }

    func toggle(_ section: SidebarSection) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }

    func expand(_ section: SidebarSection) {
        guard !expandedSections.contains(section) else { return }
        expandedSections.insert(section)
    }

    static func persistedSelection(in defaults: UserDefaults) -> SidebarItem {
        if let stored = defaults.string(forKey: SidebarItem.storageKey),
           let item = SidebarItem(rawValue: stored) {
            return item
        }
        if defaults.string(forKey: SidebarItem.storageKey) == "steamDeckSpoof" {
            defaults.set(SidebarItem.hoYoAssistant.rawValue, forKey: SidebarItem.storageKey)
            return .hoYoAssistant
        }
        if defaults.string(forKey: SidebarItem.storageKey) == "appDrop" {
            defaults.set(SidebarItem.appDropWishlist.rawValue, forKey: SidebarItem.storageKey)
            return .appDropWishlist
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

    private func persistExpandedSections() {
        defaults.set(
            expandedSections.map(\.rawValue).sorted(),
            forKey: Self.expandedSectionsKey
        )
    }
}
