import Charts
import AppDropCore
import SwiftUI

struct PriceHistoryChartView: View {
    let records: [PriceRecordSnapshot]
    let currency: String?
    @State private var range: PriceHistoryRange = .sixMonths
    @State private var hover: Hover?

    private struct Hover {
        let selection: PriceHistoryTimeline.Selection
        let x: CGFloat
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeline = PriceHistoryTimeline(records: records, currency: currency, range: range, now: context.date)
            VStack(alignment: .leading, spacing: 12) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    if timeline.points.isEmpty {
                        Text(AppStrings.string("detail.chart.empty"))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        Text(currency ?? timeline.observations.last?.currency ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                        priceChart(timeline)
                        historyNote(timeline)
                    }
                    summary(timeline)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
            }
        }
        .onChange(of: range) { _, _ in hover = nil }
        .onChange(of: records) { _, _ in hover = nil }
        .onChange(of: currency) { _, _ in hover = nil }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Text(AppStrings.string("detail.chart.title")).font(.headline)
                Spacer(minLength: 16)
                rangePicker
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.string("detail.chart.title")).font(.headline)
                rangePicker
            }
        }
    }

    private var rangePicker: some View {
        Picker(AppStrings.string("detail.chart.range"), selection: $range) {
            ForEach(PriceHistoryRange.allCases) { option in
                Text(AppStrings.string("detail.chart.range.\(option.rawValue)")).tag(option)
            }
        }
        .pickerStyle(.segmented).labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityIdentifier("priceHistoryRange")
    }

    private func priceChart(_ timeline: PriceHistoryTimeline) -> some View {
        let start = timeline.visibleStart ?? timeline.end
        // A new baseline needs a non-degenerate axis, but prices before the
        // first observation are still never drawn.
        let domainStart = min(start, timeline.end.addingTimeInterval(-60))
        let top = max(value(timeline.points.map(\.price).max() ?? 0) * 1.12, 1)
        return Chart {
            ForEach(timeline.points) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Price", value(point.price)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(LinearGradient(colors: [.primary.opacity(0.13), .primary.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value("Price", value(point.price)))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.8))
            }
            if let lowest = timeline.lowestPrice {
                RuleMark(y: .value(AppStrings.string("detail.lowestPrice"), value(lowest)))
                    .foregroundStyle(Color.green.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            ForEach(timeline.lowMarkers) { point in
                PointMark(x: .value("Date", point.date), y: .value("Price", value(point.price)))
                    .symbol {
                        Circle().fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(Circle().stroke(Color.green, lineWidth: 2))
                            .frame(width: 8, height: 8)
                    }
            }
            if timeline.points.count == 1, let point = timeline.points.first {
                PointMark(x: .value("Date", point.date), y: .value("Price", value(point.price)))
                    .foregroundStyle(Color.primary)
            }
            if let hover {
                RuleMark(x: .value("Date", hover.selection.date))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                    .lineStyle(StrokeStyle(lineWidth: 6))
                PointMark(x: .value("Date", hover.selection.date), y: .value("Price", value(hover.selection.price)))
                    .foregroundStyle(Color.primary).symbolSize(30)
            }
        }
        .chartXScale(domain: domainStart...timeline.end)
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { axis in
                AxisValueLabel {
                    if let date = axis.as(Date.self) {
                        if timeline.end.timeIntervalSince(domainStart) < 172_800 {
                            Text(dateText(date, format: "HH:mm"))
                        } else if timeline.end.timeIntervalSince(domainStart) > 31_622_400 {
                            Text(dateText(date, format: "yyyy-MM-dd"))
                        } else {
                            Text(dateText(date, format: "MM-dd"))
                        }
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plot = proxy.plotFrame else { hover = nil; return }
                                let frame = geometry[plot]
                                guard frame.contains(location),
                                      let date: Date = proxy.value(atX: location.x - frame.minX),
                                      let selection = timeline.selection(at: date) else { hover = nil; return }
                                hover = Hover(selection: selection, x: location.x)
                            case .ended:
                                hover = nil
                            }
                        }
                    if let hover {
                        tooltip(hover.selection)
                            .frame(width: 210)
                            .position(x: min(max(hover.x, 113), max(113, geometry.size.width - 113)), y: 55)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(height: 240)
        .accessibilityLabel(AppStrings.string("detail.chart.title"))
        .accessibilityIdentifier("appdrop.priceChart")
    }

    private func tooltip(_ selection: PriceHistoryTimeline.Selection) -> some View {
        VStack(spacing: 4) {
            Text(dateText(selection.date, format: "yyyy-MM-dd HH:mm:ss"))
                .font(.caption).foregroundStyle(.secondary)
            Text(selection.formattedPrice).font(.title3.weight(.semibold))
            Text(PriceFormatting.priceString(selection.price, currency: selection.currency))
                .font(.caption).foregroundStyle(.secondary)
        }
        .monospacedDigit().padding(12).frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("priceHistoryTooltip")
    }

    private func historyNote(_ timeline: PriceHistoryTimeline) -> some View {
        Group {
            if let first = timeline.firstRecordedAt {
                Text(AppStrings.format("detail.chart.recordedSince", dateText(first, format: "yyyy-MM-dd")))
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func summary(_ timeline: PriceHistoryTimeline) -> some View {
        let lowest = timeline.lowestPrice.map {
            PriceFormatting.priceString($0, currency: currency ?? timeline.observations.last?.currency ?? "")
        } ?? "—"
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                lowPriceLabel(lowest)
                lowCountLabel(timeline.lowCount)
            }
            VStack(alignment: .leading, spacing: 6) {
                lowPriceLabel(lowest)
                lowCountLabel(timeline.lowCount)
            }
        }
        .font(.callout).frame(maxWidth: .infinity, alignment: .center).padding(.top, 4)
    }

    private func lowPriceLabel(_ price: String) -> some View {
        HStack(spacing: 5) {
            Text(AppStrings.string("detail.chart.lowPrice"))
            Text(price).fontWeight(.semibold).monospacedDigit()
        }
        .foregroundStyle(.green)
    }

    private func lowCountLabel(_ count: Int) -> some View {
        Text(AppStrings.format("detail.chart.lowCount.\(range.rawValue)", count))
            .foregroundStyle(.secondary).monospacedDigit()
            .accessibilityIdentifier("priceHistoryLowCount")
    }

    private func value(_ price: Decimal) -> Double { NSDecimalNumber(decimal: price).doubleValue }

    private func dateText(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppStrings.localeIdentifier)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
