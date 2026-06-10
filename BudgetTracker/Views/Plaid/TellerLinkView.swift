import SwiftUI
import TellerKit

struct TellerLinkView: View {
    let applicationId: String
    let environmentName: String
    var reconnectEnrollmentId: String? = nil

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore

    @State private var isPresenting = false
    @State private var statusMessage = "Connect a bank account securely."
    @State private var isLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusMessage)
            Button(isLoading ? "Saving…" : (reconnectEnrollmentId == nil ? "Connect Bank" : "Reconnect Bank")) {
                isPresenting = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || applicationId.isEmpty)

            Text("Budget Tracker uses Teller when Plaid Trial connections are full. Link one bank at a time.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .tellerConnect(isPresented: $isPresenting, config: tellerConfig)
    }

    private var tellerConfig: Teller.Config {
        Teller.Config(
            appId: applicationId,
            environment: tellerEnvironment,
            enrollmentId: reconnectEnrollmentId,
            selectAccount: .disabled,
            products: [.transactions]
        ) { completion in
            handleCompletion(completion)
        }
    }

    private var tellerEnvironment: Teller.Config.Environment {
        switch environmentName.lowercased() {
        case "production":
            return .production
        case "development":
            return .development
        default:
            return .sandbox
        }
    }

    private func handleCompletion(_ completion: Teller.Config.Completion) {
        switch completion {
        case .exit:
            isPresenting = false
        case .enrollment(let authorization):
            isPresenting = false
            Task { await saveEnrollment(authorization) }
        case .failure(let error):
            isPresenting = false
            statusMessage = error.message
        default:
            isPresenting = false
        }
    }

    private func saveEnrollment(_ authorization: Teller.Authorization) async {
        guard let client = auth.activeSupabaseClient else { return }
        isLoading = true
        statusMessage = "Saving your bank connection…"
        defer { isLoading = false }

        let institutionName = authorization.enrollment.institution.name

        do {
            let response = try await SupabaseService.shared.exchangeTellerEnrollment(
                accessToken: authorization.accessToken,
                enrollmentId: authorization.enrollment.id,
                institutionName: institutionName,
                client: client
            )
            await transactions.loadAll(client: client)
            statusMessage =
                "Linked \(institutionName) (\(response.accountsLinked) accounts). " +
                "Synced \(response.synced) transactions."
        } catch {
            statusMessage = "Link succeeded but saving failed: \(error.localizedDescription)"
        }
    }
}
