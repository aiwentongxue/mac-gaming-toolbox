import Charts
import SwiftUI

/// Step chart of the price history. `.stepEnd` interpolation is used because
/// App Store prices change discretely at points in time.
struct PriceHistoryChartView: View {
    struct ChartPoint: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let price: Double
        let formatted: String
    }

    let points: [ChartPoint]
    let lowest: ChartPoint?

    var body: some View {
        Group {
            if points.isEmpty {
                placeholder(AppStrings.string("detail.chart.empty"))
            } else if points.count == 1, let point = points.first {
                VStack(alignment: .leading, spacing: 8) {
                    Chart {
                        PointMark(
                            x: .value(AppStrings.string("detail.chart.dateAxis"), point.date),
                            y: .value(AppStrings.string("detail.chart.priceAxis"), point.price)
                        )
                        .annotation(position: .top) {
                            Text(point.formatted).font(.caption)
                        }
                    }
                    Text(AppStrings.string("detail.chart.singlePoint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 200)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value(AppStrings.string("detail.chart.dateAxis"), point.date),
                            y: .value(AppStrings.string("detail.chart.priceAxis"), point.price)
                        )
                        .interpolationMethod(.stepEnd)
                    }
                    ForEach(points) { point in
                        PointMark(
                            x: .value(AppStrings.string("detail.chart.dateAxis"), point.date),
                            y: .value(AppStrings.string("detail.chart.priceAxis"), point.price)
                        )
                        .symbolSize(points.count > 30 ? 8 : 20)
                    }
                    if let lowest {
                        RuleMark(y: .value(AppStrings.string("detail.lowestPrice"), lowest.price))
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text(lowest.formatted)
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                    }
                }
                .frame(minHeight: 220)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 160)
    }
}
