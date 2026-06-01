import SwiftUI

struct RootView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var appLock: AppLockStore

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ProgressView("Loading…")
            case .unauthenticated:
                AuthView()
            case .authenticated:
                authenticatedShell
            }
        }
        .task {
            await auth.bootstrap()
        }
        .onAppear {
            appLock.refreshConfiguration()
        }
    }

    @ViewBuilder
    private var authenticatedShell: some View {
        if appLock.hasPIN {
            AppLockGateView(lock: appLock) {
                financialNavigation
            }
        } else {
            SetPINView(lock: appLock) {
                appLock.refreshConfiguration()
            }
        }
    }

    private var financialNavigation: some View {
        MainTabView()
    }
}
