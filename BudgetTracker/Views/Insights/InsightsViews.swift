import SwiftUI
import PhotosUI
import UserNotifications

struct ReceiptScanView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore

    @State private var selectedItem: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var resultMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Choose receipt photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)

            if isProcessing {
                ProgressView("Parsing receipt with Gemini…")
            }
            if let resultMessage {
                Text(resultMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Scan Receipt")
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task { await process(item) }
        }
    }

    private func process(_ item: PhotosPickerItem) async {
        isProcessing = true
        resultMessage = nil
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                resultMessage = "Could not load image."
                return
            }
            let parsed = try await GeminiService.shared.parseReceipt(imageData: data)
            await transactions.saveReceiptResult(parsed, client: auth.supabaseClient)
            resultMessage = "Saved \(parsed.merchant) for \(FinanceFormatting.currency(parsed.total)) with \(parsed.items.count) items."
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

struct SplitTransactionView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore

    let transaction: Transaction
    @State private var splits: [SplitItem]
    @State private var isSaving = false

    init(transaction: Transaction) {
        self.transaction = transaction
        _splits = State(initialValue: transaction.splitItems ?? [
            SplitItem(category: transaction.category, amount: abs(transaction.amount), note: nil)
        ])
    }

    var body: some View {
        Form {
            Section("Split items") {
                ForEach(splits.indices, id: \.self) { index in
                    Picker("Category", selection: $splits[index].category) {
                        ForEach(BudgetCategories.all, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Amount", value: $splits[index].amount, format: .currency(code: "USD"))
                }
                Button("Add line") {
                    splits.append(SplitItem(category: "Other", amount: 0, note: nil))
                }
            }
            Section {
                Text("Total split: \(FinanceFormatting.currency(splits.reduce(0) { $0 + $1.amount }))")
                Text("Transaction: \(FinanceFormatting.currency(abs(transaction.amount)))")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Split")
        .toolbar {
            Button(isSaving ? "Saving…" : "Save") {
                Task {
                    isSaving = true
                    await transactions.saveSplit(
                        transaction: transaction,
                        splitItems: splits,
                        client: auth.supabaseClient
                    )
                    isSaving = false
                }
            }
        }
    }
}

struct CategoryRulesView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var rules: MerchantRulesStore

    @State private var draft = MerchantRuleDraft()

    var body: some View {
        Form {
            Section {
                Text("Saved merchant patterns apply before AI or bank categories on every sync.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("New rule") {
                TextField("Merchant contains", text: $draft.merchantContains)
                Picker("Category", selection: $draft.category) {
                    ForEach(BudgetCategories.all, id: \.self) { Text($0).tag($0) }
                }
                Button("Add rule") {
                    Task { await rules.addRule(draft, client: auth.supabaseClient) }
                    draft.merchantContains = ""
                }
            }
            Section("Your rules library") {
                if rules.rules.isEmpty {
                    Text("No custom rules yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rules.rules) { rule in
                        VStack(alignment: .leading) {
                            Text(rule.merchantContains).font(.headline)
                            Text(rule.category).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        Task {
                            for index in indexSet {
                                await rules.deleteRule(rules.rules[index], client: auth.supabaseClient)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Category Rules")
        .task {
            guard let client = auth.activeSupabaseClient else { return }
            await rules.reload(client: client)
        }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var notifications: NotificationSettingsStore
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var transactions: TransactionStore

    var body: some View {
        Form {
            Toggle("Budget alerts", isOn: $notifications.budgetAlertsEnabled)
            Section("Alert threshold") {
                Slider(value: $notifications.alertThreshold, in: 0.5...1.0, step: 0.05) {
                    Text("Threshold")
                }
                Text("Notify when a variable category reaches \(Int(notifications.alertThreshold * 100))% of its budget. Housing, subscriptions, insurance, fixed costs, and monthly bills are excluded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Send test alert") {
                let alerts = BudgetAlertEngine.alerts(
                    progress: budgets.progress,
                    transactions: transactions.transactions,
                    threshold: notifications.alertThreshold
                )
                notifications.scheduleBudgetAlerts(messages: alerts.isEmpty ? ["Budget alerts are configured."] : alerts)
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }
}

struct BudgetHistoryView: View {
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var transactions: TransactionStore

    private var monthGroups: [TransactionMonthGroup] {
        TransactionMonthGrouping.groups(from: transactions.transactions)
    }

    var body: some View {
        List {
            if budgets.budgets.isEmpty {
                ContentUnavailableView(
                    "No budgets",
                    systemImage: "dollarsign.circle",
                    description: Text("Add budgets to see monthly spending history.")
                )
            } else if monthGroups.isEmpty {
                ContentUnavailableView(
                    "No transactions yet",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Sync transactions to build monthly history.")
                )
            } else {
                ForEach(monthGroups) { group in
                    Section(group.title) {
                        let rows = progress(for: group)
                        if rows.allSatisfy({ $0.spent == 0 }) {
                            Text("No spending recorded")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(rows.filter { $0.spent > 0 }) { row in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.category)
                                        .font(.subheadline.weight(.semibold))
                                    HStack {
                                        Text("Spent \(FinanceFormatting.currency(row.spent))")
                                        Text("of \(FinanceFormatting.currency(row.monthlyLimit))")
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.caption)
                                    if row.isOverBudget {
                                        Text("Over budget")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        HStack {
                            Text("Month total")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(FinanceFormatting.currency(rows.reduce(0) { $0 + $1.spent }))
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
        .navigationTitle("Budget History")
    }

    private func progress(for group: TransactionMonthGroup) -> [BudgetProgress] {
        guard let reference = monthReferenceDate(group.monthKey) else { return [] }
        return BudgetMath.progressRows(
            budgets: budgets.budgets,
            transactions: transactions.transactions,
            referenceDate: reference
        )
    }

    private func monthReferenceDate(_ monthKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        guard let date = formatter.date(from: monthKey) else { return nil }
        return BudgetMath.startOfMonth(date)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var appLock: AppLockStore

    var body: some View {
        List {
            if appLock.hasPIN {
                appLockEnabledSection
            } else {
                appLockSetupSection
            }
            Section("Account") {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            }
            NavigationLink("Notification settings") {
                NotificationSettingsView()
            }
            NavigationLink("Category rules") {
                CategoryRulesView()
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            appLock.refreshConfiguration()
        }
    }

    private var appLockSetupSection: some View {
        Section {
            NavigationLink {
                SetupAppLockSettingsView(lock: appLock)
            } label: {
                Label("Set up app lock", systemImage: "lock.shield")
            }
        } header: {
            Text("Security")
        } footer: {
            Text("Add a 6-digit PIN and Face ID or Touch ID. Your budget data will require unlock each time you return to the app.")
        }
    }

    private var appLockEnabledSection: some View {
        Section {
            LabeledContent("App lock", value: "On")
            if appLock.biometricsAvailable {
                Toggle("Use Face ID / Touch ID", isOn: $appLock.biometricsEnabled)
            }
            NavigationLink {
                ChangePINView(lock: appLock)
            } label: {
                Label("Change PIN", systemImage: "lock.rotation")
            }
        } header: {
            Text("Security")
        } footer: {
            if appLock.biometricsAvailable {
                Text("Face ID or Touch ID runs when you return to the app. After several failed attempts, your 6-digit PIN is required.")
            } else {
                Text("Your 6-digit PIN is required when you return to the app. Face ID is not available on this device.")
            }
        }
    }
}

struct SetupAppLockSettingsView: View {
    @ObservedObject var lock: AppLockStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SetPINView(lock: lock) {
            lock.refreshConfiguration()
            dismiss()
        }
        .navigationTitle("Set up app lock")
        .navigationBarTitleDisplayMode(.inline)
    }
}
