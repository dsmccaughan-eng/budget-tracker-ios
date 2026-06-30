import Charts
import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date
    var hasTransactions: Bool = true
    @Binding var selectedCategory: String?

    @State private var scrubBaseIndex: Int?
    @State private var lastScrubStep = 0

    private let chartDiameter: CGFloat = 290
    private let wheelHeight: CGFloat = 188
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
        // Invisible lower half so visible segments occupy the top semicircle (180°).
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
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                if chartEntries.isEmpty {
                    emptyWheel
                } else {
                    spendingWheel
                    budgetProgressRing
                }

                centerLabels
                    .frame(maxWidth: chartDiameter * 0.5)
                    .padding(.bottom, 8)
            }
            .frame(height: wheelHeight)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(scrubGesture(in: CGSize(width: chartDiameter, height: wheelHeight)))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear(perform: reconcileSelection)
        .onChange(of: slicePlan.segments.map(\.progress.category)) { _, _ in
            reconcileSelection()
        }
    }

    private var spendingWheel: some View {
        Chart(chartEntries) { entry in
            SectorMark(
                angle: .value("Amount", entry.amount),
                innerRadius: .ratio(0.66),
                angularInset: entry.isPlaceholder ? 0 : 2.5
            )
            .cornerRadius(entry.isPlaceholder ? 0 : 8)
            .foregroundStyle(entry.color)
            .annotation(position: .overlay) {
                if !entry.isPlaceholder,
                   entry.amount / max(slicePlan.total, 0.01) >= 0.1 {
                    Image(systemName: categorySymbol(entry.category))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                }
            }
        }
        .chartLegend(.hidden)
        .frame(width: chartDiameter, height: chartDiameter)
        .rotationEffect(.degrees(-90))
        .offset(y: chartDiameter * 0.21)
        .allowsHitTesting(false)
    }

    private var budgetProgressRing: some View {
        let innerDiameter = chartDiameter * 0.66
        let progressColor: Color = isOverBudget ? .red : Color(red: 0.18, green: 0.72, blue: 0.45)

        return ZStack {
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(
                    Color(.systemGray4).opacity(0.35),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
            Circle()
                .trim(from: 0, to: 0.5 * budgetProgressFraction)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
        }
        .rotationEffect(.degrees(180))
        .frame(width: innerDiameter, height: innerDiameter)
        .offset(y: chartDiameter * 0.21)
        .allowsHitTesting(false)
    }

    private var emptyWheel: some View {
        Chart {
            SectorMark(
                angle: .value("Amount", 1),
                innerRadius: .ratio(0.66),
                angularInset: 2.5
            )
            .foregroundStyle(Color(.systemGray5))
            SectorMark(
                angle: .value("Amount", 1),
                innerRadius: .ratio(0.66)
            )
            .foregroundStyle(Color(.systemGroupedBackground))
        }
        .chartLegend(.hidden)
        .frame(width: chartDiameter, height: chartDiameter)
        .rotationEffect(.degrees(-90))
        .offset(y: chartDiameter * 0.21)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var centerLabels: some View {
        if let segment = selectedSegment {
            VStack(spacing: 2) {
                Text(segment.progress.category)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(FinanceFormatting.currency(segment.amount))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 2) {
                Text(centerTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(FinanceFormatting.currency(totalCenterValue))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                if totalBudget > 0 {
                    Text("of \(FinanceFormatting.currency(totalBudget)) budget")
                        .font(.caption2)
                        .foregroundStyle(isOverBudget ? .red : .secondary)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                }
                if !usesSpendingSlices, typicalMonthly > 0 {
                    Text("Typical \(FinanceFormatting.currency(typicalMonthly))/mo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                } else if !usesSpendingSlices, !hasTransactions {
                    Text("Sync transactions to track spending")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
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

    private func scrubGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleScrubChanged(value, in: size)
            }
            .onEnded { value in
                handleScrubEnded(value, in: size)
            }
    }

    private func handleScrubChanged(_ value: DragGesture.Value, in size: CGSize) {
        let segments = slicePlan.segments
        guard !segments.isEmpty else { return }

        let layout = HalfWheelLayout(size: size)
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
                category: segmentAtStart(of: value, in: size)?.progress.category,
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

    private func handleScrubEnded(_ value: DragGesture.Value, in size: CGSize) {
        defer {
            scrubBaseIndex = nil
            lastScrubStep = 0
        }

        let moved = hypot(value.translation.width, value.translation.height)
        guard moved < 8 else { return }
        handleTap(at: value.location, in: size)
    }

    private func segmentAtStart(of value: DragGesture.Value, in size: CGSize) -> BudgetChartSliceSegment? {
        let layout = HalfWheelLayout(size: size)
        guard let fraction = layout.arcFraction(at: value.startLocation) else { return nil }
        return BudgetMath.chartSegment(
            containingArcFraction: fraction,
            segments: slicePlan.segments
        )
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let layout = HalfWheelLayout(size: size)

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

private struct HalfWheelLayout {
    let center: CGPoint
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    init(size: CGSize) {
        let width = size.width
        let height = size.height
        outerRadius = min(width * 0.46, height * 0.88)
        innerRadius = outerRadius * 0.66
        center = CGPoint(x: width / 2, y: height)
    }

    /// 0 = left (9 o'clock), 0.5 = top (12 o'clock), 1 = right (3 o'clock).
    func arcFraction(at point: CGPoint) -> Double? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius, dy <= 2 else {
            return nil
        }

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        guard degrees >= 180 || degrees == 0 else { return nil }
        if degrees == 0 { return 1 }
        return min(max((degrees - 180) / 180, 0), 1)
    }
}
