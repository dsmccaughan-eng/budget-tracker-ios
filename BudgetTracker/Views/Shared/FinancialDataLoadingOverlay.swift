import SwiftUI

struct FinancialDataLoadingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}
