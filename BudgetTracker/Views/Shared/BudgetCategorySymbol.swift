import Foundation

enum BudgetCategorySymbol {
    static func name(for category: String) -> String {
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
