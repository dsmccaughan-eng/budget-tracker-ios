import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var biometricGate = BiometricGateStore()

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView("Loading…")
            case .unauthenticated:
                AuthView()
            case .authenticated:
                BiometricGateView(gate: biometricGate) {
                    NavigationStack {
                        MainTabView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    NavigationLink {
                                        SettingsView()
                                    } label: {
                                        Image(systemName: "gearshape")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .task {
            await auth.bootstrap()
        }
    }
}
