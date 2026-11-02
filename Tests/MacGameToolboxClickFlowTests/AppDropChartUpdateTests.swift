#if !SWIFT_PACKAGE
import XCTest
import SwiftUI
import AppDropCore
@testable import Mac_游戏工具箱

@MainActor final class AppDropChartUpdateTests: XCTestCase {
    func testTutorialLinksOrderCategoriesAndSearch() throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: AppLanguage.preferenceKey)
        defer { if let old { defaults.set(old, forKey: AppLanguage.preferenceKey) } else { defaults.removeObject(forKey: AppLanguage.preferenceKey) } }
        let expected = ["https://b23.tv/JKMB60l", "https://b23.tv/8HWU3AQ", "https://b23.tv/T436Fv7", "https://b23.tv/h1XPWtM"]
        let original = ["https://b23.tv/pEOGX4P", "https://b23.tv/RiWoTPB", "https://b23.tv/V5xIKy4", "https://b23.tv/8l2dLbN", "https://b23.tv/aVH2i2K", "https://b23.tv/OZ5wkvd", "https://b23.tv/B8Fb50K", "https://b23.tv/HTFJ478", "https://b23.tv/1UfRohG", "https://b23.tv/dV7YBJQ", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ"]
        for language in [AppLanguage.Preference.simplifiedChinese, .english] {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            let all = TutorialItem.all
            XCTAssertEqual(all.count, 16)
            XCTAssertEqual(Set(all.map(\.id)).count, 16)
            XCTAssertEqual(all.first?.address, "https://b23.tv/qW8NuD7")
            XCTAssertEqual(all.first?.category, .gettingStarted)
            XCTAssertEqual(all.filter { original.contains($0.address) }.map(\.address), original)
            let anchor = try XCTUnwrap(all.firstIndex { $0.address == "https://b23.tv/HTFJ478" })
            XCTAssertEqual(Array(all[(anchor+1)...(anchor+4)]).map(\.address), expected)
            XCTAssertTrue(all[(anchor+1)...(anchor+4)].allSatisfy { $0.category == .games })
            XCTAssertEqual(TutorialItem.filtered(search: "  MetalFrame  ", category: .all).map(\.address), [expected[2]])
            XCTAssertTrue(TutorialItem.filtered(search: "MetalFrame", category: .support).isEmpty)
            XCTAssertEqual(TutorialItem.filtered(search: "", category: .games).suffix(4).map(\.address), expected)
            XCTAssertTrue(all.allSatisfy { $0.url.scheme == "https" })
        }
    }

    func testChartFitsAllLanguagesAndAppearances() throws {
        let defaults = UserDefaults.standard
        let old = defaults.object(forKey: AppLanguage.preferenceKey)
        defer { if let old { defaults.set(old, forKey: AppLanguage.preferenceKey) } else { defaults.removeObject(forKey: AppLanguage.preferenceKey) } }
        let now = Date()
        let records = [(200, "69.99"), (120, "27.99"), (80, "69.99"), (20, "27.99")].map { days, price in
            PriceRecordSnapshot(id: UUID(), trackId: "fixture", countryCode: "us", timestamp: now.addingTimeInterval(-Double(days)*86400), price: Decimal(string: price)!, formattedPrice: "$"+price, currency: "USD", recordType: .initial)
        }
        let output = URL(fileURLWithPath: "/tmp/mac-toolbox-404-chart-layout")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in AppLanguage.Preference.allCases where language != .system {
            defaults.set(language.rawValue, forKey: AppLanguage.preferenceKey)
            for scheme in [ColorScheme.light, .dark] {
                for width in [CGFloat(632), CGFloat(900)] {
                    let host = NSHostingView(rootView: PriceHistoryChartView(records: records, currency: "USD")
                        .environment(\.locale, Locale(identifier: AppStrings.localeIdentifier))
                        .preferredColorScheme(scheme).padding(20).background(AppBackgroundView()))
                    let window = NSWindow(contentRect: NSRect(x:0,y:0,width:width,height:550), styleMask:[.borderless], backing:.buffered, defer:false)
                    window.isReleasedWhenClosed=false; window.contentView=host
                    host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
                    XCTAssertLessThanOrEqual(host.fittingSize.width, width+1, "\(language) \(width)")
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in:host.bounds))
                    NSAppearance(named:scheme == .dark ? .darkAqua:.aqua)?.performAsCurrentDrawingAppearance { host.cacheDisplay(in:host.bounds,to:bitmap) }
                    try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:output.appendingPathComponent("chart-\(language.rawValue)-\(Int(width))-\(scheme == .dark ? "dark":"light").png"))
                    window.close()
                }
            }
        }
    }
}
#endif
