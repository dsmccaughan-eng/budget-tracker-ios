import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    @State private var searchText = ""
    @State private var selectedCategory: String?

    var body: some View {
        NavigationStack {
            List {
                if let summary = transactions.lastSyncSummary {
                    Section {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No transactions",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Sync from your linked accounts or connect a bank.")
                    )
                } else {
                    ForEach(groupedTransactions) { group in
                        Section(group.title) {
                            ForEach(group.transactions) { transaction in
                                NavigationLink {
                                    TransactionDetailView(transaction: transaction)
                                } label: {
                                    TransactionRowView(
                                        transaction: transaction,
                                        account: transactions.account(for: transaction.accountId)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Merchant or category")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("All categories") { selectedCategory = nil }
                        ForEach(BudgetCategories.all, id: \.self) { category in
                            Button(category) { selectedCategory = category }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        ReceiptScanView()
                    } label: {
                        Image(systemName: "doc.viewfinder")
                    }
                    NavigationLink {
                        AccountsView()
                    } label: {
                        Image(systemName: "building.columns")
                    }
                    Button {
                        Task { await transactions.sync(client: auth.supabaseClient) }
                    } label: {
                        if transactions.isSyncing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(transactions.isSyncing)
                }
            }
            .refreshable {
                await transactions.loadAll(client: auth.supabaseClient)
                await budgets.reload(client: auth.supabaseClient, transactions: transactions.transactions)
            }
        }
    }

    private var filtered: [Transaction] {
        transactions.filteredTransactions(search: searchText, category: selectedCategory)
    }

    private var groupedTransactions: [TransactionMonthGroup] {
        TransactionMonthGrouping.groups(from: filtered)
    }
}
