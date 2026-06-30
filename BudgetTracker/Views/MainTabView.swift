import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            TransactionListView()
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }

            BudgetView()
                .tabItem { Label("Budgets", systemImage: "dollarsign.circle") }
        }
    }
}
