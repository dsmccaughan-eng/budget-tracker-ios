import LinkKit
import SwiftUI

struct PlaidLinkView: View {
    var updatePlaidItemId: String? = nil

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var plaidLink: PlaidLinkCoordinator
    @State private var linkToken: String?
    @State private var statusMessage = "Connect a bank account via Plaid Link."
    @State private var isLoading = false
    @State private var isPresentingLink = false

    private var isUpdateMode: Bool { updatePlaidItemId != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(statusMessage)
            Button(isLoading ? "Loading…" : (isUpdateMode ? "Reconnect Bank" : "Connect Bank")) {
                Task { await prepareLink() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
        }
        .padding()
        .navigationTitle(isUpdateMode ? "Reconnect Bank" : "Link Account")
        .sheet(isPresented: $isPresentingLink, onDismiss: { linkToken = nil }) {
            if let linkToken {
                PlaidLinkPresenter(
                    linkToken: linkToken,
                    coordinator: plaidLink,
                    onSuccess: { success in
                        if isUpdateMode {
                            Task { await finishUpdateMode() }
                        } else {
                            Task { await exchangeToken(success) }
                        }
                    },
                    onExit: { exit in
                        statusMessage = Self.exitMessage(exit)
                            ?? "Could not open bank link. Try again."
                        isPresentingLink = false
                    }
                )
            }
        }
    }

    private static func exitMessage(_ exit: LinkExit?) -> String? {
        guard let exit else { return nil }
        if let error = exit.error {
            let detail = error.errorMessage
            if detail.lowercased().contains("post process") {
                return """
                Bank login finished but the app could not complete setup. \
                If you use Chase, BofA, or similar, OAuth redirect must be configured in Plaid Dashboard. \
                (\(detail))
                """
            }
            return detail
        }
        switch exit.metadata.status {
        case .requiresCredentials:
            return "Bank linking was cancelled."
        default:
            break
        }
        return nil
    }

    private func prepareLink() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: LinkTokenResponse
            if let updatePlaidItemId {
                response = try await SupabaseService.shared.createUpdateLinkToken(
                    plaidItemId: updatePlaidItemId,
                    client: auth.supabaseClient
                )
            } else {
                response = try await SupabaseService.shared.invokeFunction(
                    name: "plaid-create-link-token",
                    client: auth.supabaseClient
                )
            }
            linkToken = response.linkToken
            isPresentingLink = true
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func exchangeToken(_ success: LinkSuccess) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: ExchangeTokenResponse = try await SupabaseService.shared.invokeFunction(
                name: "plaid-exchange-token",
                body: ExchangeTokenBody(
                    publicToken: success.publicToken,
                    institutionName: success.metadata.institution.name
                ),
                client: auth.supabaseClient
            )
            statusMessage = "Linked \(success.metadata.institution.name) with \(response.accountsLinked) accounts."
            isPresentingLink = false
            await transactions.loadAll(client: auth.supabaseClient)
            _ = try? await SupabaseService.shared.syncTransactions(client: auth.supabaseClient)
            await transactions.loadAll(client: auth.supabaseClient)
        } catch {
            statusMessage = "Link succeeded but saving failed: \(error.localizedDescription)"
        }
    }

    private func finishUpdateMode() async {
        isLoading = true
        defer { isLoading = false }

        isPresentingLink = false
        statusMessage = "Bank connection refreshed."
        await transactions.loadAll(client: auth.supabaseClient)
        _ = try? await SupabaseService.shared.syncTransactions(client: auth.supabaseClient)
        await transactions.loadAll(client: auth.supabaseClient)
    }
}

private struct PlaidLinkPresenter: UIViewControllerRepresentable {
    let linkToken: String
    let coordinator: PlaidLinkCoordinator
    let onSuccess: (LinkSuccess) -> Void
    let onExit: (LinkExit?) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            coordinator.open(
                linkToken: linkToken,
                presenting: controller,
                onSuccess: onSuccess,
                onExit: onExit
            )
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
