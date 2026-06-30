import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date
    var hasTransactions: Bool = true
    @Binding var selectedCategory: String?

    @State private var scrubBaseIndex: Int?
    @State private var lastScrubStep = 0

    private let wheelHeight: CGFloat = 168
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

    private var centerTitle: String {
        usesSpendingSlices ? "Spent" : "Budgeted"
    }

    private var typicalMonthly: Double {
        progress.reduce(0) { $0 + $1.projectedSpend }
    }

    private var selectedSegment: BudgetChartSliceSegment? {
        guard let selectedCategory else { return nil }
        return slicePlan.segments.first { $0.progress.category == selectedCategory }
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    if slicePlan.segments.isEmpty {
                        BudgetWheelSliceShape(startFraction: 0, endFraction: 1)
                            .stroke(
                                Color(.systemGray4),
                                style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                            )
                    } else {
                        ForEach(slicePlan.segments, id: \.progress.category) { segment in
                            BudgetWheelSliceShape(
                                startFraction: segment.startFraction,
                                endFraction: segment.endFraction
                            )
                            .fill(Color(hex: segment.progress.color))
                            .overlay {
                                if selectedCategory == segment.progress.category {
                                    BudgetWheelSliceShape(
                                        startFraction: segment.startFraction,
                                        endFraction: segment.endFraction
                                    )
                                    .stroke(Color.primary.opacity(0.35), lineWidth: 2.5)
                                }
                            }
                        }
                    }

                    centerLabels
                        .frame(maxWidth: geo.size.width * 0.62)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 6)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(scrubGesture(in: geo.size))
            }
            .frame(height: wheelHeight)
            .drawingGroup()

            if slicePlan.segments.isEmpty {
                EmptyView()
            } else if selectedCategory != nil {
                Text("Slide to browse · tap to show all")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if usesSpendingSlices {
                Text("Slide across the chart to browse categories")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onAppear(perform: reconcileSelection)
        .onChange(of: slicePlan.segments.map(\.progress.category)) { _, _ in
            reconcileSelection()
        }
    }

    @ViewBuilder
    private var centerLabels: some View {
        if let segment = selectedSegment {
            VStack(spacing: 3) {
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 3) {
                Text(centerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(FinanceFormatting.currency(totalCenterValue))
                    .font(.title2.weight(.bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(referenceDate.formatted(.dateTime.month(.wide)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}

private struct BudgetWheelSliceShape: Shape {
    let startFraction: Double
    let endFraction: Double

    func path(in rect: CGRect) -> Path {
        let layout = HalfWheelLayout(size: rect.size)
        let startAngle = layout.angle(for: startFraction)
        let endAngle = layout.angle(for: endFraction)
        var path = Path()
        path.addArc(
            center: layout.center,
            radius: layout.outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        path.addArc(
            center: layout.center,
            radius: layout.innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct HalfWheelLayout {
    let center: CGPoint
    let outerRadius: CGFloat
    let innerRadius: CGFloat

    init(size: CGSize) {
        let width = size.width
        let height = size.height
        outerRadius = min(width * 0.44, height * 0.82)
        innerRadius = outerRadius * 0.58
        center = CGPoint(x: width / 2, y: height)
    }

    /// 0 = left (9 o'clock), 0.5 = top (12 o'clock), 1 = right (3 o'clock).
    func angle(for fraction: Double) -> Angle {
        Angle.degrees(180 + fraction * 180)
    }

    func arcFraction(at point: CGPoint) -> Double? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius, dy <= 0 else {
            return nil
        }

        var degrees = atan2(dy, dx) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        guard degrees >= 180 || degrees == 0 else { return nil }
        if degrees == 0 { return 1 }
        return min(max((degrees - 180) / 180, 0), 1)
    }
}
