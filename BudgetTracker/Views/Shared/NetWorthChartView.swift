import Charts
import SwiftUI

struct NetWorthChartView: View {
    let points: [NetWorthChartPoint]
    @Binding var selectedRange: NetWorthTimeRange
    var title: String = "NET WORTH"
    var allowsMonthlyGranularity: Bool = false

    @State private var selectedPoint: NetWorthChartPoint?
    @State private var granularity: NetWorthChartGranularity = .daily

    private var displayPoints: [NetWorthChartPoint] {
        guard allowsMonthlyGranularity, granularity == .monthly else { return points }
        return NetWorthHistoryEngine.monthlyChartPoints(from: points)
    }

    private var displayPoint: NetWorthChartPoint? {
        selectedPoint ?? displayPoints.last
    }

    private var change: (amount: Double, percent: Double)? {
        guard let point = displayPoint else { return nil }
        if allowsMonthlyGranularity, granularity == .monthly {
            return NetWorthHistoryEngine.changeFromPrevious(selected: point, series: displayPoints)
        }
        return NetWorthHistoryEngine.changeFromStart(selected: point, series: displayPoints)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeader
            chartBody
            if allowsMonthlyGranularity {
                granularityPicker
            }
            rangePicker
        }
        .onAppear {
            selectedPoint = displayPoints.last
        }
        .onChange(of: displayPoints.map(\.id)) { _, _ in
            if let selectedPoint,
               !displayPoints.contains(where: { $0.id == selectedPoint.id }) {
                self.selectedPoint = displayPoints.last
            } else if selectedPoint == nil {
                selectedPoint = displayPoints.last
            }
        }
        .onChange(of: granularity) { _, _ in
            selectedPoint = displayPoints.last
        }
    }

    private var chartHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(FinanceFormatting.currency(displayPoint?.netWorth ?? 0))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer()
            if let point = displayPoint {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(point.date, format: dateFormat)
                        .font(.caption.weight(.semibold))
                    if let change {
                        changeLabel(change)
                    }
                    if allowsMonthlyGranularity, granularity == .monthly, change != nil {
                        Text("vs previous month")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func changeLabel(_ change: (amount: Double, percent: Double)) -> some View {
        let positive = change.amount >= 0
        HStack(spacing: 4) {
            Image(systemName: positive ? "arrow.up.right" : "arrow.down.right")
            Text("\(FinanceFormatting.currency(abs(change.amount))) (\(abs(change.percent), format: .number.precision(.fractionLength(1)))%)")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(positive ? Color.green : Color.red)
    }

    @ViewBuilder
    private var chartBody: some View {
        if displayPoints.count < 2 {
            ContentUnavailableView {
                Label("Building history", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Capture snapshots over time or link accounts to track net worth on the chart.")
            }
            .frame(height: 200)
        } else {
            Chart {
                ForEach(displayPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Net worth", point.netWorth)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.35),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Net worth", point.netWorth)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.linear)
                }

                if let selected = displayPoint {
                    RuleMark(x: .value("Date", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Color.primary.opacity(0.45))

                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Net worth", selected.netWorth)
                    )
                    .symbolSize(70)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(compactCurrency(amount))
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectPoint(at: value.location, proxy: proxy, geometry: geometry)
                                }
                        )
                }
            }
            .frame(height: 220)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(NetWorthTimeRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedRange == range
                                ? Color(.systemGray5)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func selectPoint(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        let x = location.x - origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        selectedPoint = NetWorthHistoryEngine.nearestPoint(to: date, in: displayPoints)
    }

    private var dateFormat: Date.FormatStyle {
        if allowsMonthlyGranularity, granularity == .monthly {
            return .dateTime.month(.abbreviated).year()
        }
        return .dateTime.day().month(.abbreviated).year()
    }

    private var granularityPicker: some View {
        HStack(spacing: 6) {
            ForEach(NetWorthChartGranularity.allCases) { option in
                Button {
                    granularity = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            granularity == option
                                ? Color(.systemGray5)
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Chart interval")
    }

    private func compactCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        }
        if absValue >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return FinanceFormatting.currency(value)
    }
}
