import SwiftUI
import PhotosUI
import UserNotifications

struct ReceiptScanView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var priceHistory: PriceHistoryStore

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
            let priceItems = parsed.items.map {
                PriceHistoryItem(
                    id: UUID(),
                    itemName: $0.name,
                    price: $0.price,
                    merchant: parsed.merchant,
                    date: parsed.date
                )
            }
            await priceHistory.addItems(priceItems, client: auth.supabaseClient)
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
            Section("Your rules") {
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
        .task { await rules.reload(client: auth.supabaseClient) }
    }
}

struct NotificationSettingsView: View {
    @EnvironmentObject private var notifications: NotificationSettingsStore
    @EnvironmentObject private var budgets: BudgetStore

    var body: some View {
        Form {
            Toggle("Budget alerts", isOn: $notifications.budgetAlertsEnabled)
            Section("Alert threshold") {
                Slider(value: $notifications.alertThreshold, in: 0.5...1.0, step: 0.05) {
                    Text("Threshold")
                }
                Text("Notify when a category reaches \(Int(notifications.alertThreshold * 100))% of its budget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Send test alert") {
                let alerts = BudgetAlertEngine.alerts(
                    progress: budgets.progress,
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

struct PriceHistoryView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var priceHistory: PriceHistoryStore

    var body: some View {
        List {
            if priceHistory.items.isEmpty {
                ContentUnavailableView(
                    "No price history",
                    systemImage: "tag",
                    description: Text("Scan receipts to track item prices over time.")
                )
            } else {
                ForEach(priceHistory.items) { item in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(item.itemName).font(.headline)
                            Text(item.merchant).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(FinanceFormatting.currency(item.price))
                            Text(item.date).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Price History")
        .task { await priceHistory.reload(client: auth.supabaseClient) }
    }
}

struct SubscriptionAuditView: View {
    @EnvironmentObject private var insights: InsightsStore

    var body: some View {
        List {
            Section("Monthly recurring total") {
                Text(FinanceFormatting.currency(SubscriptionAuditEngine.totalMonthlySpend(insights.subscriptions)))
                    .font(.title2.bold())
            }
            Section("Detected subscriptions") {
                if insights.subscriptions.isEmpty {
                    Text("No recurring subscription charges found yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(insights.subscriptions) { charge in
                        VStack(alignment: .leading) {
                            Text(charge.merchant).font(.headline)
                            Text("\(FinanceFormatting.currency(charge.monthlyAmount))/mo • \(charge.chargeCount) charges")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
    }
}

struct InsightsView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var insights: InsightsStore
    @EnvironmentObject private var transactions: TransactionStore
    @EnvironmentObject private var budgets: BudgetStore

    var body: some View {
        NavigationStack {
            List {
                Section("AI summary") {
                    if insights.isLoading {
                        ProgressView("Generating insights…")
                    } else if let insight = insights.latestInsight {
                        Text(insight.summary)
                        Label(insight.topInsight, systemImage: "lightbulb")
                        Label(insight.suggestion, systemImage: "arrow.up.right")
                        ForEach(insight.anomalies, id: \.self) { anomaly in
                            Label(anomaly, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Text("Generate a weekly AI summary from your spending.")
                            .foregroundStyle(.secondary)
                    }
                    Button("Generate insights") {
                        Task {
                            await insights.generateWeeklyInsight(
                                transactions: transactions.transactions,
                                budgets: budgets.budgets,
                                progress: budgets.progress
                            )
                        }
                    }
                    .disabled(insights.isLoading || !APIKeys.hasValidGeminiKey)
                }

                Section("Tools") {
                    NavigationLink("Subscription audit") {
                        SubscriptionAuditView()
                    }
                    NavigationLink("Price history") {
                        PriceHistoryView()
                    }
                }
            }
            .navigationTitle("Insights")
            .onAppear {
                insights.refreshLocal(transactions: transactions.transactions)
            }
        }
    }
}

struct BudgetHistoryView: View {
    @EnvironmentObject private var budgets: BudgetStore

    var body: some View {
        List(budgets.progress) { row in
            VStack(alignment: .leading, spacing: 4) {
                Text(row.category).font(.headline)
                Text("Spent \(FinanceFormatting.currency(row.spent)) of \(FinanceFormatting.currency(row.monthlyLimit))")
                    .font(.caption)
                if row.isOverBudget {
                    Text("Over budget")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Budget History")
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
