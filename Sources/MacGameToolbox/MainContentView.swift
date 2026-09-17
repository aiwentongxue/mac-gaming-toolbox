#if SWIFT_PACKAGE
import MacGameToolboxClickFlow
#endif
import AppKit
import SwiftUI

enum MainSection: String, CaseIterable {
    case toolbox
    case clickFlow

    static let storageKey = "mainSelectedSection"

    static func persisted(in defaults: UserDefaults = .standard) -> MainSection {
        guard let value = defaults.string(forKey: storageKey) else { return .toolbox }
        return MainSection(rawValue: value) ?? .toolbox
    }
}

struct MainContentView: View {
    @AppStorage(MainSection.storageKey) private var storedSection = MainSection.toolbox.rawValue
    @ObservedObject var clickFlowController: ClickFlowFeatureController
    @EnvironmentObject private var localization: LocalizationController

    private var selection: MainSection {
        get { MainSection(rawValue: storedSection) ?? .toolbox }
        nonmutating set { storedSection = newValue.rawValue }
    }

    var body: some View {
        Group {
            switch selection {
            case .toolbox:
                DashboardView()
            case .clickFlow:
                ClickFlowFeatureView(controller: clickFlowController) {
                    selection = .toolbox
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowTitlebarSectionSwitcher(selection: Binding(
            get: { selection },
            set: { selection = $0 }
        )))
        .onAppear { synchronizeClickFlowLanguage() }
        .onChange(of: localization.refreshToken) { _, _ in synchronizeClickFlowLanguage() }
    }

    private func synchronizeClickFlowLanguage() {
        let language: ClickFlowLanguage
        switch AppLanguage.currentLanguage {
        case .simplifiedChinese: language = .simplifiedChinese
        case .traditionalChinese: language = .traditionalChinese
        case .english, .system: language = .english
        case .japanese: language = .japanese
        case .korean: language = .korean
        case .german: language = .german
        case .french: language = .french
        case .spanish: language = .spanish
        case .portuguese: language = .portuguese
        }
        clickFlowController.setLanguage(language)
    }
}

private struct WindowTitlebarSectionSwitcher: NSViewRepresentable {
    @Binding var selection: MainSection

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WindowAttachmentView {
        let view = WindowAttachmentView()
        view.onWindowChange = { window in
            context.coordinator.install(in: window, selection: $selection)
        }
        return view
    }

    func updateNSView(_ nsView: WindowAttachmentView, context: Context) {
        context.coordinator.install(in: nsView.window, selection: $selection)
    }

    static func dismantleNSView(_ nsView: WindowAttachmentView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var installedWindow: NSWindow?
        private weak var titlebarView: NSView?
        private weak var segmentedControl: NSSegmentedControl?
        private var selectionBinding: Binding<MainSection>?

        func install(in window: NSWindow?, selection: Binding<MainSection>) {
            guard let window else { return }

            if installedWindow !== window {
                uninstall()
            }
            selectionBinding = selection

            if let segmentedControl {
                update(segmentedControl, selection: selection.wrappedValue)
                bringSwitcherToFront()
                return
            }

            guard let closeButton = window.standardWindowButton(.closeButton),
                  let titlebarView = closeButton.superview else {
                return
            }

            let segmentedControl = NSSegmentedControl(
                labels: [tr("工具箱", "Toolbox"), "ClickFlow"],
                trackingMode: .selectOne,
                target: self,
                action: #selector(sectionChanged(_:))
            )
            segmentedControl.translatesAutoresizingMaskIntoConstraints = false
            segmentedControl.segmentStyle = .automatic
            segmentedControl.segmentDistribution = .fillEqually
            segmentedControl.controlSize = .regular
            segmentedControl.setAccessibilityIdentifier("main.section.switcher")
            update(segmentedControl, selection: selection.wrappedValue)
            titlebarView.addSubview(segmentedControl, positioned: .above, relativeTo: nil)

            NSLayoutConstraint.activate([
                segmentedControl.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
                segmentedControl.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                segmentedControl.widthAnchor.constraint(equalToConstant: 290),
                segmentedControl.heightAnchor.constraint(equalToConstant: 34)
            ])

            installedWindow = window
            self.titlebarView = titlebarView
            self.segmentedControl = segmentedControl
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
            bringSwitcherToFront()
        }

        @objc private func sectionChanged(_ sender: NSSegmentedControl) {
            selectionBinding?.wrappedValue = sender.selectedSegment == 1 ? .clickFlow : .toolbox
        }

        private func update(_ control: NSSegmentedControl, selection: MainSection) {
            control.setLabel(tr("工具箱", "Toolbox"), forSegment: 0)
            control.setLabel("ClickFlow", forSegment: 1)
            control.selectedSegment = selection == .toolbox ? 0 : 1
            control.setAccessibilityLabel(tr("主页面", "Main Section"))
            control.setAccessibilityValue(selection == .toolbox ? tr("工具箱", "Toolbox") : "ClickFlow")
        }

        @objc private func windowDidUpdate(_ notification: Notification) {
            bringSwitcherToFront()
        }

        private func bringSwitcherToFront() {
            // NavigationSplitView rebuilds NSToolbarView after a tab change. Keep the
            // host switcher last in hit-test order so the visible control stays clickable.
            guard let titlebarView, let segmentedControl,
                  titlebarView.subviews.last !== segmentedControl else {
                return
            }

            var subviews = titlebarView.subviews
            guard let index = subviews.firstIndex(where: { $0 === segmentedControl }) else {
                return
            }
            subviews.append(subviews.remove(at: index))
            titlebarView.subviews = subviews
        }

        func uninstall() {
            NotificationCenter.default.removeObserver(self)
            segmentedControl?.removeFromSuperview()
            segmentedControl = nil
            titlebarView = nil
            installedWindow = nil
            selectionBinding = nil
        }
    }
}

private final class WindowAttachmentView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
