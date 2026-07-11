import Foundation
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

enum AppLanguage {
    static var isChinese: Bool {
        guard let preferred = Locale.preferredLanguages.first else { return false }
        return Locale(identifier: preferred).language.languageCode == .chinese
    }

    static func text(_ chinese: String, _ english: String) -> String {
        isChinese ? chinese : english
    }

    static func phase(_ phase: TaskPhase) -> String {
        switch phase {
        case .idle: text("空闲", "Idle")
        case .awaitingAuthorization: text("等待授权", "Awaiting authorization")
        case .running: text("进行中", "Running")
        case .succeeded: text("已完成", "Completed")
        case .failed: text("失败", "Failed")
        case .cancelled: text("已取消", "Cancelled")
        }
    }
}

@inline(__always)
func tr(_ chinese: String, _ english: String) -> String {
    AppLanguage.text(chinese, english)
}
