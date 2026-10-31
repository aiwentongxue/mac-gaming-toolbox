import AppKit
import SwiftUI

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.035, green: 0.045, blue: 0.07), Color(red: 0.08, green: 0.055, blue: 0.13)]
                : [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.98, green: 0.94, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct ToolboxPage<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let maxContentWidth: CGFloat
    @ViewBuilder let content: Content

    init(
        icon: String,
        title: String,
        subtitle: String,
        maxContentWidth: CGFloat = 980,
        @ViewBuilder content: () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.maxContentWidth = maxContentWidth
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ToolboxPageHeader(icon: icon, title: title, subtitle: subtitle)
                content
            }
            .frame(maxWidth: maxContentWidth, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.automatic)
    }
}

struct ToolboxPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    init(icon: String, title: String, subtitle: String) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 44, height: 44)
                .background(.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ToolboxCard<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolboxCard()
    }
}

struct ToolboxStatusBar: View {
    @EnvironmentObject private var model: AppModel
    let onDismiss: () -> Void

    var body: some View {
        if model.status.phase != .idle {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(model.status.message)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let progress = model.status.progress {
                    ProgressView(value: progress)
                        .frame(minWidth: 120, maxWidth: 220)
                }
                Spacer(minLength: 8)
                if model.isHoYoAssistantRunning {
                    Button(tr("取消并恢复 hosts", "Cancel and Restore Hosts")) {
                        model.cancelHoYoAssistant()
                    }
                    .controlSize(.small)
                }
                Text(AppLanguage.phase(model.status.phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help(tr("关闭状态提示", "Dismiss Status"))
                .accessibilityLabel(tr("关闭状态提示", "Dismiss Status"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var statusIcon: String {
        switch model.status.phase {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .awaitingAuthorization: "lock.shield.fill"
        default: "gearshape.2.fill"
        }
    }

    private var statusColor: Color {
        switch model.status.phase {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        case .awaitingAuthorization: .orange
        default: .purple
        }
    }
}

struct WindowAppearanceConfigurator: NSViewRepresentable {
    let colorScheme: ColorScheme
    let nativeGlassEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = true
        window.backgroundColor = colorScheme == .dark
            ? NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.07, alpha: 1)
            : NSColor(calibratedRed: 0.965, green: 0.97, blue: 0.995, alpha: 1)
        window.animationBehavior = nativeGlassEnabled ? .default : .none
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = window.backgroundColor?.cgColor
    }
}

private struct ToolboxCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        content
            .background(
                colorScheme == .dark ? Color.black.opacity(0.42) : Color.white.opacity(0.72),
                in: shape
            )
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(
                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                    lineWidth: 0.7
                )
            )
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}

extension View {
    func toolboxCard() -> some View {
        modifier(ToolboxCardModifier())
    }

    @ViewBuilder
    func toolboxProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
