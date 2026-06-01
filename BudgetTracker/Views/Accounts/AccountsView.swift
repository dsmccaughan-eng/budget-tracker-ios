import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @State private var itemPendingRemoval: PlaidItem?

    var body: some View {
        List {
            if !transactions.plaidItems.isEmpty {
                Section("Connections") {
                    ForEach(transactions.plaidItems) { item in
                        PlaidConnectionRow(item: item)
                    }
                }
            }

            Section("Accounts") {
                if transactions.accounts.isEmpty {
                    ContentUnavailableView(
                        "No accounts linked",
                        systemImage: "building.columns",
                        description: Text("Connect a bank account to sync balances and transactions.")
                    )
                } else {
                    ForEach(transactions.accounts) { account in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(FinanceFormatting.accountLabel(account))
                                .font(.headline)
                            Text(account.type.capitalized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let balance = account.currentBalance {
                                Text(FinanceFormatting.currency(balance))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink("Link bank") {
                    PlaidLinkView()
                }
                Button {
                    Task { await transactions.refreshAccountsFromPlaid(client: auth.supabaseClient) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(transactions.isLoading)
            }
        }
        .refreshable {
            await transactions.loadAll(client: auth.supabaseClient)
        }
        .confirmationDialog(
            "Disconnect this bank?",
            isPresented: Binding(
                get: { itemPendingRemoval != nil },
                set: { if !$0 { itemPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let item = itemPendingRemoval else { return }
                Task {
                    await transactions.removePlaidItem(item, client: auth.supabaseClient)
                    itemPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                itemPendingRemoval = nil
            }
        } message: {
            Text("This removes linked accounts and synced transactions for that bank from Budget Tracker. Your bank login is revoked with Plaid.")
        }
    }

    @ViewBuilder
    private func PlaidConnectionRow(item: PlaidItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.institutionName ?? "Bank connection")
                    .font(.headline)
                Spacer()
                ConnectionStatusBadge(status: item.status)
            }

            if let message = item.errorMessage, item.needsReconnect {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if item.needsReconnect {
                    NavigationLink("Reconnect") {
                        PlaidLinkView(updatePlaidItemId: item.plaidItemId)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Disconnect", role: .destructive) {
                    itemPendingRemoval = item
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ConnectionStatusBadge: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch status {
        case "active": return "Active"
        case "login_required": return "Reconnect needed"
        case "pending_disconnect": return "Pending disconnect"
        case "revoked": return "Revoked"
        default: return "Attention"
        }
    }

    private var color: Color {
        switch status {
        case "active": return .green
        case "login_required", "error", "pending_disconnect": return .orange
        case "revoked": return .red
        default: return .secondary
        }
    }
}
