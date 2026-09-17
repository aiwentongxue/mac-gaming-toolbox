import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarPage

    var body: some View {
        List(SidebarPage.allCases, selection: $selection) { page in
            Label(page.title, systemImage: page.systemImage)
                .tag(page)
        }
    }
}

private extension SidebarPage {
    var title: String {
        switch self {
        case .clicker: cf("sidebar.clicker")
        case .macros: cf("sidebar.macros")
        case .combinedMacros: cf("sidebar.combinedMacros")
        case .settings: cf("sidebar.settings")
        }
    }

    var systemImage: String {
        switch self {
        case .clicker: "cursorarrow.click.2"
        case .macros: "record.circle"
        case .combinedMacros: "gamecontroller"
        case .settings: "gearshape"
        }
    }
}
