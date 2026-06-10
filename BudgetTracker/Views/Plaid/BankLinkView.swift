import SwiftUI

/// Unified bank link entry: server picks Plaid or Teller; product UI stays unchanged after linking.
struct BankLinkView: View {
    var reconnectConnection: BankConnection? = nil

    @EnvironmentObject private var auth: AuthStore
    @State private var policy: LinkPolicyResponse?
    @State private var statusMessage = "Loading link options…"
    @State private var isLoading = true
    @State private var loadError: String?

    private var isReconnect: Bool { reconnectConnection != nil }

    var body: some View {
        Group {
            if let loadError {
                VStack(alignment: .leading, spacing: 12) {
                    Text(loadError)
                        .foregroundStyle(.red)
                    Button("Try again") {
                        Task { await loadPolicy() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else if isLoading {
                ProgressView(statusMessage)
                    .padding()
            } else if let reconnectConnection {
                reconnectContent(for: reconnectConnection)
            } else if let policy {
                newLinkContent(policy: policy)
            } else {
                Text("Unable to start bank linking.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .navigationTitle(isReconnect ? "Reconnect Bank" : "Link Account")
        .task {
            await loadPolicy()
        }
    }

    @ViewBuilder
    private func newLinkContent(policy: LinkPolicyResponse) -> some View {
        switch policy.provider {
        case .plaid:
            PlaidLinkView()
        case .teller:
            if let teller = policy.teller {
                TellerLinkView(
                    applicationId: teller.applicationId,
                    environmentName: teller.environment
                )
            } else {
                fallbackWhenTellerUnavailable(policy: policy)
            }
        }
    }

    @ViewBuilder
    private func reconnectContent(for connection: BankConnection) -> some View {
        switch connection.provider {
        case .plaid:
            if let plaidItemId = connection.plaidItemId {
                PlaidLinkView(updatePlaidItemId: plaidItemId)
            }
        case .teller:
            if let enrollmentId = connection.tellerEnrollmentId,
               let teller = policy?.teller {
                TellerLinkView(
                    applicationId: teller.applicationId,
                    environmentName: teller.environment,
                    reconnectEnrollmentId: enrollmentId
                )
            } else {
                Text("Reconnect is not available for this connection.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private func fallbackWhenTellerUnavailable(policy: LinkPolicyResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Teller is not configured on the server yet.")
                .foregroundStyle(.secondary)
            if policy.plaidItemCount < policy.plaidTrialLimit {
                PlaidLinkView()
            } else {
                Text(
                    "Plaid Trial limit reached (\(policy.plaidItemCount)/\(policy.plaidTrialLimit)). " +
                    "Add TELLER_APPLICATION_ID to Supabase secrets or upgrade Plaid."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private func loadPolicy() async {
        guard let client = auth.activeSupabaseClient else {
            loadError = "Sign in required."
            isLoading = false
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            policy = try await SupabaseService.shared.fetchLinkPolicy(client: client)
            if reconnectConnection == nil, let policy {
                statusMessage = policy.provider == .teller
                    ? "Connecting via Teller (Plaid Trial full)."
                    : "Connecting via Plaid."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
