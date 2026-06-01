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
            self?.linkHandler = nil
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

    /// LinkKit 5+ resumes OAuth automatically when the handler is retained; keep for logging.
    func continueLink(from url: URL) -> Bool {
        guard linkHandler != nil else { return false }
        NSLog("Plaid OAuth return URL: %@", url.absoluteString)
        return true
    }

    var hasActiveSession: Bool {
        linkHandler != nil
    }
}
