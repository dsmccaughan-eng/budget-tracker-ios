import Charts
import SwiftUI

struct AccountBalanceChartView: View {
    let accountLabel: String
    let points: [AccountBalancePoint]
    @Binding var selectedRange: NetWorthTimeRange

    @State private var selectedPoint: AccountBalancePoint?

    private var displayPoint: AccountBalancePoint? {
        selectedPoint ?? points.last
    }

    private var change: (amount: Double, percent: Double)? {
        guard let point = displayPoint else { return nil }
        guard let first = points.first else { return nil }
        guard first.balance != 0 else {
            let amount = point.balance - first.balance
            return amount == 0 ? nil : (amount, 0)
        }
        let amount = point.balance - first.balance
        let percent = amount / abs(first.balance) * 100
        return (amount, percent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartHeader
            chartBody
            rangePicker
        }
        .onAppear {
            selectedPoint = points.last
        }
        .onChange(of: points.map(\.id)) { _, _ in
            if let selectedPoint,
               !points.contains(where: { $0.id == selectedPoint.id }) {
                self.selectedPoint = points.last
            } else if selectedPoint == nil {
                selectedPoint = points.last
            }
        }
    }

    private var chartHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(FinanceFormatting.currency(displayPoint?.balance ?? 0))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Spacer()
            if let point = displayPoint {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(point.date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption.weight(.semibold))
                    if let change {
                        changeLabel(change)
                    }
                    if point.source == .reconstructed {
                        Text("Estimated from activity")
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
        if points.count < 2 {
            ContentUnavailableView {
                Label("Not enough history", systemImage: "chart.xyaxis.line")
            } description: {
                Text("Link this account and sync transactions to see estimated balances for the past year.")
            }
            .frame(height: 200)
        } else {
            Chart {
                ForEach(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
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
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", point.balance)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                }

                if let selected = displayPoint {
                    RuleMark(x: .value("Date", selected.date))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .foregroundStyle(Color.primary.opacity(0.45))

                    PointMark(
                        x: .value("Date", selected.date),
                        y: .value("Balance", selected.balance)
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
        let plotFrame = proxy.plotFrame
        let origin = geometry[plotFrame].origin
        let x = location.x - origin.x
        guard let date: Date = proxy.value(atX: x) else { return }
        selectedPoint = nearestPoint(to: date)
    }

    private func nearestPoint(to date: Date) -> AccountBalancePoint? {
        points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
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
