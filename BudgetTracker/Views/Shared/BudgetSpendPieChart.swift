import Charts
import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date
    var hasTransactions: Bool = true
    @Binding var selectedCategory: String?

    @State private var scrubBaseIndex: Int?
    @State private var lastScrubStep = 0

    private let segmentInnerRadiusRatio: CGFloat = 0.64
    private let scrubStepPoints: CGFloat = 26

    init(
        progress: [BudgetProgress],
        referenceDate: Date,
        hasTransactions: Bool = true,
        selectedCategory: Binding<String?> = .constant(nil)
    ) {
        self.progress = progress
        self.referenceDate = referenceDate
        self.hasTransactions = hasTransactions
        _selectedCategory = selectedCategory
    }

    private var slicePlan: (total: Double, segments: [BudgetChartSliceSegment]) {
        BudgetMath.chartSliceSegments(progress: progress)
    }

    private var usesSpendingSlices: Bool {
        BudgetMath.usesSpendingChartSlices(progress: progress)
    }

    private var totalCenterValue: Double {
        slicePlan.total
    }

    private var totalBudget: Double {
        progress.reduce(0) { $0 + $1.monthlyLimit }
    }

    private var isOverBudget: Bool {
        totalBudget > 0 && totalCenterValue > totalBudget
    }

    private var centerTitle: String {
        usesSpendingSlices ? "Spent" : "Budgeted"
    }

    private var budgetProgressFraction: Double {
        guard totalBudget > 0 else { return 0 }
        return min(totalCenterValue / totalBudget, 1)
    }

    private var typicalMonthly: Double {
        progress.reduce(0) { $0 + $1.projectedSpend }
    }

    private var selectedSegment: BudgetChartSliceSegment? {
        guard let selectedCategory else { return nil }
        return slicePlan.segments.first { $0.progress.category == selectedCategory }
    }

    private var chartEntries: [BudgetWheelChartEntry] {
        let plan = slicePlan
        guard !plan.segments.isEmpty else { return [] }
        var entries = plan.segments.map { segment in
            BudgetWheelChartEntry(
                id: segment.progress.category,
                category: segment.progress.category,
                amount: segment.amount,
                color: Color(hex: segment.progress.color)
            )
        }
        entries.append(
            BudgetWheelChartEntry(
                id: "__placeholder__",
                category: "",
                amount: plan.total,
                color: Color(.systemGroupedBackground)
            )
        )
        return entries
    }

    var body: some View {
        GeometryReader { geo in
            let metrics = BudgetWheelMetrics(
                width: geo.size.width,
                innerRadiusRatio: segmentInnerRadiusRatio
            )

            ZStack {
                let arcCenter = metrics.arcCenter(in: geo.size)

                if chartEntries.isEmpty {
                    emptyWheel(metrics: metrics)
                        .position(arcCenter)
                } else {
                    spendingWheel(metrics: metrics)
                        .position(arcCenter)
                    budgetProgressRing(metrics: metrics)
                        .position(arcCenter)
                    categoryIcons(metrics: metrics, containerSize: geo.size)
                }

                centerLabels
                    .frame(maxWidth: metrics.labelMaxWidth, minHeight: metrics.labelAreaHeight, alignment: .bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, metrics.labelBottomPadding)
            }
            .frame(width: geo.size.width, height: metrics.totalHeight, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(
                scrubGesture(
                    in: CGSize(width: geo.size.width, height: metrics.totalHeight),
                    metrics: metrics
                )
            )
        }
        .frame(height: BudgetWheelMetrics.preferredTotalHeight)
        .padding(.vertical, 4)
        .onAppear(perform: reconcileSelection)
        .onChange(of: slicePlan.segments.map(\.progress.category)) { _, _ in
            reconcileSelection()
        }
    }

    private func spendingWheel(metrics: BudgetWheelMetrics) -> some View {
        Chart(chartEntries) { entry in
            SectorMark(
                angle: .value("Amount", entry.amount),
                innerRadius: .ratio(segmentInnerRadiusRatio),
                angularInset: entry.isPlaceholder ? 0 : 2.5
            )
            .cornerRadius(entry.isPlaceholder ? 0 : 8)
            .foregroundStyle(entry.color)
        }
        .chartLegend(.hidden)
        .frame(width: metrics.chartDiameter, height: metrics.chartDiameter)
        .rotationEffect(.degrees(-90))
        .allowsHitTesting(false)
    }

    private func categoryIcons(metrics: BudgetWheelMetrics, containerSize: CGSize) -> some View {
        ZStack {
            ForEach(slicePlan.segments, id: \.progress.category) { segment in
                if segment.amount / max(slicePlan.total, 0.01) >= 0.1 {
                    let midFraction = (segment.startFraction + segment.endFraction) / 2
                    let point = metrics.pointOnArc(
                        fraction: midFraction,
                        radiusRatio: metrics.iconRadiusRatio,
                        in: containerSize
                    )
                    Image(systemName: categorySymbol(segment.progress.category))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .position(point)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func budgetProgressRing(metrics: BudgetWheelMetrics) -> some View {
        let progressColor: Color = isOverBudget ? .red : Color(red: 0.18, green: 0.72, blue: 0.45)

        return ZStack {
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(
                    Color(.systemGray4).opacity(0.3),
                    style: StrokeStyle(lineWidth: metrics.progressLineWidth, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: 0.5 * budgetProgressFraction)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: metrics.progressLineWidth, lineCap: .round)
                )
        }
        .rotationEffect(.degrees(180))
        .frame(width: metrics.progressRingDiameter, height: metrics.progressRingDiameter)
        .allowsHitTesting(false)
    }

    private func emptyWheel(metrics: BudgetWheelMetrics) -> some View {
        Chart {
            SectorMark(
                angle: .value("Amount", 1),
                innerRadius: .ratio(segmentInnerRadiusRatio),
                angularInset: 2.5
            )
            .foregroundStyle(Color(.systemGray5))
            SectorMark(
                angle: .value("Amount", 1),
                innerRadius: .ratio(segmentInnerRadiusRatio)
            )
            .foregroundStyle(Color(.systemGroupedBackground))
        }
        .chartLegend(.hidden)
        .frame(width: metrics.chartDiameter, height: metrics.chartDiameter)
        .rotationEffect(.degrees(-90))
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var centerLabels: some View {
        if let segment = selectedSegment {
            VStack(spacing: 1) {
                Text(segment.progress.category)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(FinanceFormatting.currency(segment.amount))
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 1) {
                Text(centerTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(FinanceFormatting.currency(totalCenterValue))
                    .font(.title3.weight(.bold))
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                if totalBudget > 0 {
                    Text("of \(FinanceFormatting.currency(totalBudget)) budget")
                        .font(.caption2)
                        .foregroundStyle(isOverBudget ? .red : .secondary)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                }
                if !usesSpendingSlices, typicalMonthly > 0 {
                    Text("Typical \(FinanceFormatting.currency(typicalMonthly))/mo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else if !usesSpendingSlices, !hasTransactions {
                    Text("Sync transactions to track spending")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else if !usesSpendingSlices, hasTransactions {
                    Text("No spending this month yet")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func reconcileSelection() {
        guard let selectedCategory else { return }
        let isVisible = slicePlan.segments.contains { $0.progress.category == selectedCategory }
        if !isVisible {
            self.selectedCategory = nil
        }
    }

    private func scrubGesture(in size: CGSize, metrics: BudgetWheelMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleScrubChanged(value, in: size, metrics: metrics)
            }
            .onEnded { value in
                handleScrubEnded(value, in: size, metrics: metrics)
            }
    }

    private func handleScrubChanged(
        _ value: DragGesture.Value,
        in size: CGSize,
        metrics: BudgetWheelMetrics
    ) {
        let segments = slicePlan.segments
        guard !segments.isEmpty else { return }

        let layout = HalfWheelLayout(size: size, metrics: metrics)
        if let fraction = layout.arcFraction(at: value.location),
           let segment = BudgetMath.chartSegment(containingArcFraction: fraction, segments: segments) {
            scrubBaseIndex = nil
            lastScrubStep = 0
            selectedCategory = segment.progress.category
            return
        }

        if scrubBaseIndex == nil {
            scrubBaseIndex = BudgetMath.chartSegmentIndex(
                category: selectedCategory,
                segments: segments
            ) ?? BudgetMath.chartSegmentIndex(
                category: segmentAtStart(of: value, in: size, metrics: metrics)?.progress.category,
                segments: segments
            ) ?? 0
            lastScrubStep = 0
        }

        let step = Int(value.translation.width / scrubStepPoints)
        guard step != lastScrubStep else { return }
        lastScrubStep = step

        guard let base = scrubBaseIndex,
              let segment = BudgetMath.chartSegment(atStep: step, from: base, segments: segments) else {
            return
        }
        selectedCategory = segment.progress.category
    }

    private func handleScrubEnded(
        _ value: DragGesture.Value,
        in size: CGSize,
        metrics: BudgetWheelMetrics
    ) {
        defer {
            scrubBaseIndex = nil
            lastScrubStep = 0
        }

        let moved = hypot(value.translation.width, value.translation.height)
        guard moved < 8 else { return }
        handleTap(at: value.location, in: size, metrics: metrics)
    }

    private func segmentAtStart(
        of value: DragGesture.Value,
        in size: CGSize,
        metrics: BudgetWheelMetrics
    ) -> BudgetChartSliceSegment? {
        let layout = HalfWheelLayout(size: size, metrics: metrics)
        guard let fraction = layout.arcFraction(at: value.startLocation) else { return nil }
        return BudgetMath.chartSegment(
            containingArcFraction: fraction,
            segments: slicePlan.segments
        )
    }

    private func handleTap(at location: CGPoint, in size: CGSize, metrics: BudgetWheelMetrics) {
        let layout = HalfWheelLayout(size: size, metrics: metrics)

        guard let fraction = layout.arcFraction(at: location),
              let segment = BudgetMath.chartSegment(
                containingArcFraction: fraction,
                segments: slicePlan.segments
              ) else {
            selectedCategory = nil
            return
        }

        if selectedCategory == segment.progress.category {
            selectedCategory = nil
        } else {
            selectedCategory = segment.progress.category
        }
    }

    private func categorySymbol(_ category: String) -> String {
        switch category {
        case "Housing & Utilities":
            return "house.fill"
        case "Groceries":
            return "cart.fill"
        case "Transport", "Transportation":
            return "car.fill"
        case "Dining & Bars", "Food & Dining":
            return "fork.knife"
        case "Shopping":
            return "bag.fill"
        case "Investments":
            return "chart.line.uptrend.xyaxis"
        case "Transfers":
            return "arrow.left.arrow.right"
        case "Health & Wellness":
            return "heart.fill"
        case "Subscriptions":
            return "play.rectangle.fill"
        case "Income":
            return "dollarsign.circle.fill"
        default:
            return "tag.fill"
        }
    }
}

private struct BudgetWheelChartEntry: Identifiable {
    let id: String
    let category: String
    let amount: Double
    let color: Color

    var isPlaceholder: Bool { id == "__placeholder__" }
}

private struct BudgetWheelMetrics {
    let chartDiameter: CGFloat
    let totalHeight: CGFloat
    let innerRadiusRatio: CGFloat
    let progressRingDiameter: CGFloat
    let progressLineWidth: CGFloat
    let iconRadiusRatio: CGFloat
    let labelAreaHeight: CGFloat
    let labelBottomPadding: CGFloat
    let labelMaxWidth: CGFloat

    static var preferredTotalHeight: CGFloat {
        let metrics = BudgetWheelMetrics(width: 320, innerRadiusRatio: 0.64)
        return metrics.totalHeight
    }

    init(width: CGFloat, innerRadiusRatio: CGFloat) {
        self.innerRadiusRatio = innerRadiusRatio
        chartDiameter = min(max(width - 24, 240), 272)
        let outerRadius = chartDiameter / 2
        labelAreaHeight = 74
        labelBottomPadding = 12
        progressLineWidth = 3
        labelMaxWidth = chartDiameter * 0.52
        iconRadiusRatio = (1 + innerRadiusRatio) / 2

        let labelReserve = labelAreaHeight + labelBottomPadding
        totalHeight = outerRadius + labelReserve + 8

        // Slightly outside the chart inner radius so the stroke hugs the category band.
        progressRingDiameter = chartDiameter * (innerRadiusRatio + 0.022)
    }

    func arcCenter(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2,
            y: totalHeight - labelAreaHeight - labelBottomPadding
        )
    }

    func pointOnArc(fraction: Double, radiusRatio: CGFloat, in size: CGSize) -> CGPoint {
        let center = arcCenter(in: size)
        let radius = (chartDiameter / 2) * radiusRatio
        let radians = (180 + fraction * 180) * .pi / 180
        return CGPoint(
            x: center.x + radius * CGFloat(cos(radians)),
            y: center.y + radius * CGFloat(sin(radians))
        )
    }
}

private struct HalfWheelLayout {
    let center: CGPoint
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    init(size: CGSize, metrics: BudgetWheelMetrics) {
        outerRadius = metrics.chartDiameter / 2
        innerRadius = outerRadius * metrics.innerRadiusRatio
        center = metrics.arcCenter(in: size)
    }

    func arcFraction(at point: CGPoint) -> Double? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius * 0.92, distance <= outerRadius * 1.04, dy <= 6 else {
            return nil
        }

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        guard degrees >= 180 || degrees == 0 else { return nil }
        if degrees == 0 { return 1 }
        return min(max((degrees - 180) / 180, 0), 1)
    }
}
