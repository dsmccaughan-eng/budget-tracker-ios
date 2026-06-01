import Foundation
import LinkKit
import UIKit

/// Retains the Plaid Link `Handler` for the full Link + OAuth flow (required by LinkKit).
@MainActor
final class PlaidLinkCoordinator: NSObject, ObservableObject {
    private var linkHandler: Handler?

    func open(
        linkToken: String,
        presenting: UIViewController,
        onSuccess: @escaping (LinkSuccess) -> Void,
        onExit: @escaping (LinkExit?) -> Void
    ) {
        var configuration = LinkTokenConfiguration(token: linkToken) { [weak self] success in
            self?.linkHandler = nil
            onSuccess(success)
        }
        configuration.onExit = { [weak self] exit in
            // Keep handler through OAuth handoff (Robinhood, Chase, etc.) until success or real error.
            if exit.error != nil {
                self?.linkHandler = nil
            }
            onExit(exit)
        }

        switch Plaid.create(configuration) {
        case .failure:
            linkHandler = nil
            onExit(nil)
        case .success(let handler):
            linkHandler = handler
            handler.open(presentUsing: .viewController(presenting))
        }
    }

    /// LinkKit 5 resumes OAuth when the handler is retained and iOS opens the app via Universal Link or URL scheme.
    func continueLink(from url: URL) -> Bool {
        guard isPlaidOAuthReturn(url) else { return false }
        NSLog("Plaid OAuth return URL: %@", url.absoluteString)
        guard linkHandler != nil else {
            NSLog("Plaid OAuth return ignored — no active Link handler (re-open Connect Bank)")
            return false
        }
        return true
    }

    func endSession() {
        linkHandler = nil
    }

    var hasActiveSession: Bool {
        linkHandler != nil
    }

    private func isPlaidOAuthReturn(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "com.optimized.budgettracker" {
            return url.host?.lowercased() == "plaid"
        }
        if url.scheme?.lowercased() == "https",
           url.host?.lowercased() == "dsmccaughan-eng.github.io" {
            return url.path.contains("/plaid/")
        }
        return false
    }
}
