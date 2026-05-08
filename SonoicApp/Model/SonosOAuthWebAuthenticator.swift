import AuthenticationServices
import Foundation
import UIKit

@MainActor
final class SonosOAuthWebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    enum AuthenticationError: LocalizedError {
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .couldNotStart:
                "Sonoic couldn't start Sonos sign-in."
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }

                continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session

            guard session.start() else {
                self.session = nil
                continuation.resume(throwing: AuthenticationError.couldNotStart)
                return
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                Self.activePresentationAnchor()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                Self.activePresentationAnchor()
            }
        }
    }

    @MainActor
    private static func activePresentationAnchor() -> ASPresentationAnchor {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let keyWindow = windowScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        {
            return keyWindow
        }

        guard let windowScene = windowScenes.first else {
            preconditionFailure("Sonos sign-in requires an active window scene.")
        }

        return ASPresentationAnchor(windowScene: windowScene)
    }
}
