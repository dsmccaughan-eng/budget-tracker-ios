import SwiftUI
import Supabase

struct AccountsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var accountBalances: AccountBalanceStore
    @EnvironmentObject private var netWorth: NetWorthStore
    @State private var connectionPendingRemoval: BankConnection?

    var body: some View {
        List {
            if !transactions.bankConnections.isEmpty {
                Section("Connections") {
                    ForEach(transactions.bankConnections) { connection in
                        BankConnectionRow(connection: connection)
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
                        NavigationLink {
                            AccountDetailView(account: account)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(FinanceFormatting.accountLabel(account))
                                        .font(.headline)
                                    Text(accountSubtitle(account))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let balance = account.currentBalance {
                                    Text(FinanceFormatting.currency(
                                        AccountBalanceHistoryEngine.displayBalance(
                                            balance,
                                            accountType: account.type
                                        )
                                    ))
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink("Link bank") {
                    BankLinkView()
                }
                Button {
                    Task {
                        guard let client = auth.activeSupabaseClient else { return }
                        await transactions.refreshAccountsFromPlaid(
                            client: client,
                            userId: auth.userId
                        )
                        await reloadAccountSnapshots(client: client)
                        await reloadNetWorth(client: client)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh account balances")
                .disabled(transactions.isLoading)
            }
        }
        .refreshable {
            await reloadAccounts()
        }
        .task {
            guard transactions.accounts.isEmpty,
                  !transactions.bankConnections.isEmpty || !transactions.transactions.isEmpty else { return }
            await reloadAccounts()
        }
        .confirmationDialog(
            "Disconnect this bank?",
            isPresented: Binding(
                get: { connectionPendingRemoval != nil },
                set: { if !$0 { connectionPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let connection = connectionPendingRemoval,
                      let client = auth.activeSupabaseClient else { return }
                Task {
                    await transactions.removeBankConnection(connection, client: client)
                    connectionPendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) {
                connectionPendingRemoval = nil
            }
        } message: {
            Text(disconnectMessage)
        }
    }

    private var disconnectMessage: String {
        guard let connection = connectionPendingRemoval else {
            return "This removes linked accounts and synced transactions for that bank."
        }
        switch connection.provider {
        case .plaid:
            return "This removes linked accounts and synced transactions. Your bank login is revoked with Plaid."
        case .teller:
            return "This removes linked accounts and synced transactions. Your Teller enrollment is removed from Budget Tracker."
        }
    }

    private func accountSubtitle(_ account: Account) -> String {
        let typeLabel = account.type.capitalized
        if account.provider == "teller" {
            return "\(typeLabel) · Teller"
        }
        return typeLabel
    }

    private func reloadAccounts() async {
        guard let client = auth.activeSupabaseClient else { return }
        await transactions.loadAll(client: client)
        await transactions.refreshPlaidAccountsIfNeeded(
            client: client,
            userId: auth.userId
        )
        await reloadAccountSnapshots(client: client)
    }

    private func reloadAccountSnapshots(client: SupabaseClient) async {
        await accountBalances.reload(client: client)
        await accountBalances.recordTodaySnapshots(accounts: transactions.accounts, client: client)
    }

    private func reloadNetWorth(client: SupabaseClient) async {
        await netWorth.reload(
            client: client,
            accounts: transactions.accounts,
            accountSnapshots: accountBalances.snapshots,
            transactions: transactions.transactions
        )
        await netWorth.recordDailySnapshotIfNeeded(
            client: client,
            accounts: transactions.accounts,
            accountBalances: accountBalances
        )
    }

    @ViewBuilder
    private func BankConnectionRow(connection: BankConnection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(connection.institutionName ?? "Bank connection")
                    .font(.headline)
                Spacer()
                ConnectionStatusBadge(status: connection.status)
                ProviderBadge(provider: connection.provider)
            }

            if let message = connection.errorMessage, connection.needsReconnect {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                if connection.needsReconnect {
                    NavigationLink("Reconnect") {
                        BankLinkView(reconnectConnection: connection)
                    }
                    .buttonStyle(.bordered)
                }

                Button("Disconnect", role: .destructive) {
                    connectionPendingRemoval = connection
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProviderBadge: View {
    let provider: BankConnection.Provider

    var body: some View {
        Text(provider == .plaid ? "Plaid" : "Teller")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
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
        case "revoked", "disconnected": return "Disconnected"
        default: return "Attention"
        }
    }

    private var color: Color {
        switch status {
        case "active": return .green
        case "login_required", "error", "pending_disconnect", "disconnected": return .orange
        case "revoked": return .red
        default: return .secondary
        }
    }
}
