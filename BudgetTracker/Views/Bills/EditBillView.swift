import SwiftUI

struct EditBillView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @Environment(\.dismiss) private var dismiss

    let transactionId: UUID

    @State private var nickname = ""
    @State private var dueDay = 1
    @State private var amount: Double = 0
    @State private var isSaving = false
    @State private var showSaveError = false

    private var anchor: Transaction? {
        transactions.transactions.first { $0.id == transactionId && $0.isFixedBill }
    }

    var body: some View {
        Form {
            if let anchor {
                Section("Bill") {
                    TextField("Nickname", text: $nickname)
                    Picker("Typical due day", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text("Day \(day)").tag(day)
                        }
                    }
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                }

                Section("Source transaction") {
                    LabeledContent("Merchant", value: FinanceFormatting.displayName(for: anchor))
                    LabeledContent("Category", value: anchor.category)
                    LabeledContent("Last charge", value: anchor.date)
                }

                Section {
                    Button("Remove from bills", role: .destructive) {
                        Task { await save(isFixedBill: false) }
                    }
                }

                if let errorMessage = transactions.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Bill not found",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("This bill may have been removed.")
                )
            }
        }
        .navigationTitle("Edit bill")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDraft)
        .alert("Could not save bill", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transactions.errorMessage ?? "Try again.")
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "Saving…" : "Save") {
                    Task { await save(isFixedBill: true) }
                }
                .disabled(isSaving || anchor == nil || amount <= 0)
            }
        }
    }

    private func loadDraft() {
        guard let anchor else { return }
        nickname = BillsEngine.displayName(for: anchor)
        dueDay = BillsEngine.resolvedDueDay(
            for: anchor,
            transactions: transactions.transactions
        )
        amount = BillsEngine.resolvedAmount(for: anchor)
    }

    private func save(isFixedBill: Bool) async {
        guard let client = auth.activeSupabaseClient, let anchor else { return }
        isSaving = true
        defer { isSaving = false }

        let trimmedNickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        await transactions.updateBillSettings(
            transaction: anchor,
            isFixedBill: isFixedBill,
            billNickname: trimmedNickname.isEmpty ? nil : trimmedNickname,
            billDueDay: dueDay,
            billAmount: amount,
            client: client
        )
        if transactions.errorMessage == nil {
            dismiss()
        } else {
            showSaveError = true
        }
    }
}
