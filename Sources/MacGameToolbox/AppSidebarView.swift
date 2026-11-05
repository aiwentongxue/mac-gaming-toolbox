import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif

struct AppSidebarView: View {
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var clickFlowController: ClickFlowFeatureController
    @EnvironmentObject private var localization: LocalizationController
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(SidebarSection.allCases) { section in
                Section {
                    if navigation.isExpanded(section) {
                        ForEach(section.items.filter { $0 != .settings }) { item in
                            SidebarLabel(
                                item: item,
                                badge: badge(for: item),
                                isActive: item == .cfClicker ||
                                    item == .cfMacros ||
                                    item == .cfCombinedMacros
                                    ? clickFlowController.isAutomationActive
                                    : false
                            )
                            .tag(item)
                            .accessibilityIdentifier("sidebar.\(item.rawValue)")
                        }
                    }
                } header: {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            navigation.toggle(section)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .frame(width: 12)
                                .rotationEffect(
                                    .degrees(navigation.isExpanded(section) ? 90 : 0)
                                )
                            Text(section.localizedTitle)
                                .font(.caption.weight(.semibold))
                                .textCase(nil)
                            Spacer(minLength: 2)
                        }
                        .padding(.leading, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(section.localizedTitle)
                    .accessibilityValue(
                        navigation.isExpanded(section)
                            ? tr("已展开", "Expanded")
                            : tr("已收起", "Collapsed")
                    )
                    .accessibilityHint(tr("切换侧边栏分组", "Toggle sidebar group"))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button {
                    navigation.select(.settings)
                } label: {
                    SidebarLabel(item: .settings, badge: nil, isActive: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(navigation.selection == .settings ? Color.white : Color.primary)
                        .background(
                            navigation.selection == .settings ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sidebar.settings")
                .accessibilityAddTraits(navigation.selection == .settings ? [.isSelected] : [])
                .padding(10)
            }
            .background(.regularMaterial)
        }
        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
    }

    private var selectionBinding: Binding<SidebarItem?> {
        Binding(
            get: { navigation.selection == .settings ? nil : navigation.selection },
            set: { item in
                if let item {
                    navigation.select(item)
                }
            }
        )
    }

    private func badge(for item: SidebarItem) -> String? {
        switch item {
        case .metalHUD:
            return model.metalHUDEnabled ? tr("开", "ON") : nil
        case .diskManager:
            return model.disks.isEmpty ? nil : "\(model.disks.count)"
        case .cfClicker, .cfMacros, .cfCombinedMacros:
            return clickFlowController.isAutomationActive ? tr("运行中", "ACTIVE") : nil
        case .appDropWishlist, .appDropTodayDrops, .appDropHistoricalLows, .appDropSettings:
            return nil
        default:
            return nil
        }
    }
}

private struct SidebarLabel: View {
    @EnvironmentObject private var localization: LocalizationController
    let item: SidebarItem
    let badge: String?
    let isActive: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.iconName)
                .frame(width: 18)
            Text(item.sidebarTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                    .symbolEffect(.pulse, options: .repeating)
                    .accessibilityHidden(true)
            } else if let badge {
                Text(badge)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
