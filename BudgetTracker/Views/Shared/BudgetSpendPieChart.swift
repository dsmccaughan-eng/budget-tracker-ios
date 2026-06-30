import SwiftUI

struct BudgetSpendPieChart: View {
    let progress: [BudgetProgress]
    let referenceDate: Date
    var hasTransactions: Bool = true
    @Binding var selectedCategory: String?

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

    private var usesSpendingSlices: Bool {
        BudgetMath.monthSpendingDisplayTotal(progress: progress) > 0
    }

    private var slices: [BudgetProgress] {
        if usesSpendingSlices {
            return progress.filter { $0.listDisplaySpent > 0 }
                .sorted { $0.listDisplaySpent > $1.listDisplaySpent }
        }
        return progress.filter { $0.monthlyLimit > 0 }
            .sorted { $0.monthlyLimit > $1.monthlyLimit }
    }

    private var totalCenterValue: Double {
        if usesSpendingSlices {
            return BudgetMath.totalSpent(slices)
        }
        return slices.reduce(0) { $0 + $1.monthlyLimit }
    }

    private var centerTitle: String {
        usesSpendingSlices ? "Spent" : "Budgeted"
    }

    private var typicalMonthly: Double {
        progress.reduce(0) { $0 + $1.projectedSpend }
    }

    private var selectedRow: BudgetProgress? {
        guard let selectedCategory else { return nil }
        return slices.first { $0.category == selectedCategory }
    }

    private var sliceTotal: Double {
        max(slices.reduce(0) { $0 + sliceAmount(for: $1) }, 0.01)
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack {
                    if slices.isEmpty {
                        Canvas { context, size in
                            let layout = HalfWheelLayout(size: size)
                            var path = Path()
                            path.addArc(
                                center: layout.center,
                                radius: (layout.outerRadius + layout.innerRadius) / 2,
                                startAngle: .degrees(180),
                                endAngle: .degrees(0),
                                clockwise: true
                            )
                            context.stroke(
                                path,
                                with: .color(Color(.systemGray4)),
                                style: StrokeStyle(lineWidth: layout.ringWidth, dash: [6, 4])
                            )
                        }
                        .allowsHitTesting(false)
                    } else {
                        Canvas { context, size in
                            drawHalfWheel(context: &context, size: size)
                        }
                        .contentShape(HalfWheelHitShape())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    handleTap(at: value.location, in: geo.size)
                                }
                        )
                    }

                    centerLabels
                        .frame(maxWidth: geo.size.width * 0.62)
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * 0.78
                        )
                }
            }
            .frame(height: 168)

            if selectedCategory != nil {
                Text("Tap the chart again to show all categories")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if usesSpendingSlices, !slices.isEmpty {
                Text("Tap a slice for details")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var centerLabels: some View {
        if let row = selectedRow {
            VStack(spacing: 3) {
                Text(row.category)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(FinanceFormatting.currency(sliceAmount(for: row)))
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

    private func drawHalfWheel(context: inout GraphicsContext, size: CGSize) {
        let layout = HalfWheelLayout(size: size)
        var cumulative = 0.0

        for row in slices {
            let amount = sliceAmount(for: row)
            let sliceFraction = amount / sliceTotal
            let startFraction = cumulative
            let endFraction = cumulative + sliceFraction
            cumulative = endFraction

            var sliceContext = context
            sliceContext.opacity = fadedOpacity(for: row)

            let path = donutSlicePath(
                layout: layout,
                startFraction: startFraction,
                endFraction: endFraction
            )
            sliceContext.fill(path, with: .color(Color(hex: row.color)))

            if selectedCategory == row.category {
                sliceContext.stroke(
                    path,
                    with: .color(.primary.opacity(0.25)),
                    lineWidth: 2
                )
            }
        }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        guard !slices.isEmpty else { return }
        let layout = HalfWheelLayout(size: size)

        guard let fraction = layout.arcFraction(at: location) else {
            selectedCategory = nil
            return
        }

        var cumulative = 0.0
        for row in slices {
            let sliceFraction = sliceAmount(for: row) / sliceTotal
            if fraction <= cumulative + sliceFraction + 0.0001 {
                if selectedCategory == row.category {
                    selectedCategory = nil
                } else {
                    selectedCategory = row.category
                }
                return
            }
            cumulative += sliceFraction
        }
    }

    private func donutSlicePath(
        layout: HalfWheelLayout,
        startFraction: Double,
        endFraction: Double
    ) -> Path {
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

    private func fadedOpacity(for row: BudgetProgress) -> Double {
        guard selectedCategory != nil else { return usesSpendingSlices ? 1 : 0.9 }
        return selectedCategory == row.category ? 1 : 0.32
    }

    private func sliceAmount(for row: BudgetProgress) -> Double {
        usesSpendingSlices ? row.listDisplaySpent : row.monthlyLimit
    }
}

private struct HalfWheelLayout {
    let center: CGPoint
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let ringWidth: CGFloat

    init(size: CGSize) {
        let width = size.width
        let height = size.height
        outerRadius = min(width * 0.46, height * 0.88)
        innerRadius = outerRadius * 0.62
        ringWidth = outerRadius - innerRadius
        center = CGPoint(x: width / 2, y: height * 0.96)
    }

    func angle(for fraction: Double) -> Angle {
        Angle.degrees(180 - fraction * 180)
    }

    /// Maps a tap to 0…1 along the top semicircle (left → top → right).
    func arcFraction(at point: CGPoint) -> Double? {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius, distance <= outerRadius, dy < 0 else {
            return nil
        }

        let angle = atan2(dy, dx)
        let fraction: Double
        if angle <= 0 {
            fraction = 0.5 + (angle / -.pi) * 0.5
        } else {
            fraction = (1 - angle / .pi) * 0.5
        }
        return min(max(fraction, 0), 1)
    }
}

/// Limits taps to the upper semicircle so list scrolling does not steal chart hits.
private struct HalfWheelHitShape: Shape {
    func path(in rect: CGRect) -> Path {
        let layout = HalfWheelLayout(size: rect.size)
        var path = Path()
        path.addArc(
            center: layout.center,
            radius: layout.outerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.addLine(to: CGPoint(x: layout.center.x, y: layout.center.y))
        path.closeSubpath()
        return path
    }
}
