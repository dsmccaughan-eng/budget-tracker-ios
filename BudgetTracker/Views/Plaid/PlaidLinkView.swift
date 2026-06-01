import LinkKit
import SwiftUI

struct PlaidLinkView: View {
    var updatePlaidItemId: String? = nil

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
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
                    onSuccess: { publicToken in
                        if isUpdateMode {
                            Task { await finishUpdateMode() }
                        } else {
                            Task { await exchangeToken(publicToken) }
                        }
                    },
                    onExit: {
                        isPresentingLink = false
                    }
                )
            }
        }
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

    private func exchangeToken(_ publicToken: String) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: ExchangeTokenResponse = try await SupabaseService.shared.invokeFunction(
                name: "plaid-exchange-token",
                body: ExchangeTokenBody(publicToken: publicToken, institutionName: nil),
                client: auth.supabaseClient
            )
            statusMessage = "Linked item \(response.itemId) with \(response.accountsLinked) accounts."
            isPresentingLink = false
            await transactions.loadAll(client: auth.supabaseClient)
            _ = try? await SupabaseService.shared.syncTransactions(client: auth.supabaseClient)
            await transactions.loadAll(client: auth.supabaseClient)
        } catch {
            statusMessage = error.localizedDescription
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
    let onSuccess: (String) -> Void
    let onExit: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        DispatchQueue.main.async {
            var configuration = LinkTokenConfiguration(token: linkToken) { success in
                onSuccess(success.publicToken)
            }
            configuration.onExit = { _ in onExit() }
            let result = Plaid.create(configuration)
            switch result {
            case .failure:
                onExit()
            case .success(let handler):
                handler.open(presentUsing: .viewController(controller))
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
