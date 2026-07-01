import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case transactions
    case budgets
    case netWorth
}

struct MainTabView: View {
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                .tag(AppTab.dashboard)

            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)

            BudgetView()
                .tabItem { Label("Budgets", systemImage: "dollarsign.circle") }
                .tag(AppTab.budgets)

            NavigationStack {
                NetWorthView()
            }
            .tabItem { Label("Net Worth", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(AppTab.netWorth)
        }
    }
}
