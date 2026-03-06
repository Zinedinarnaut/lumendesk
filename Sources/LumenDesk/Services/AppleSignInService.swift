import AuthenticationServices
import Foundation

@MainActor
final class AppleSignInService: NSObject, ObservableObject {
    struct Session: Equatable {
        let userID: String
        let email: String?
        let fullName: String?
        let identityToken: String
        let authorizationCode: String?
    }

    @Published private(set) var session: Session?
    @Published private(set) var statusMessage: String?

    private let defaults = UserDefaults.standard
    private let savedUserIDKey = "marketplace.apple.userID"

    override init() {
        super.init()
        refreshCredentialState()
    }

    var isSignedIn: Bool {
        session != nil
    }

    var authToken: String? {
        session?.identityToken
    }

    var userID: String? {
        session?.userID
    }

    func configureAppleIDRequest(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func handleAuthorization(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                statusMessage = "Sign in failed: invalid Apple credential type."
                return
            }

            guard
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8),
                !token.isEmpty
            else {
                statusMessage = "Sign in succeeded, but Apple did not return an identity token."
                return
            }

            let authorizationCode = credential.authorizationCode
                .flatMap { String(data: $0, encoding: .utf8) }
            let fullName = credential.fullName
                .flatMap { PersonNameComponentsFormatter().string(from: $0) }
                .flatMap { $0.isEmpty ? nil : $0 }

            session = Session(
                userID: credential.user,
                email: credential.email,
                fullName: fullName,
                identityToken: token,
                authorizationCode: authorizationCode
            )
            defaults.set(credential.user, forKey: savedUserIDKey)
            statusMessage = "Signed in with Apple."

        case .failure(let error):
            statusMessage = "Apple sign in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        session = nil
        defaults.removeObject(forKey: savedUserIDKey)
        statusMessage = "Signed out."
    }

    private func refreshCredentialState() {
        guard
            let storedUserID = defaults.string(forKey: savedUserIDKey),
            !storedUserID.isEmpty
        else {
            return
        }

        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: storedUserID) { [weak self] state, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.statusMessage = "Could not verify saved Apple login state: \(error.localizedDescription)"
                    return
                }

                switch state {
                case .authorized:
                    self.statusMessage = "Sign in with Apple to refresh marketplace token."
                case .revoked, .notFound:
                    self.signOut()
                default:
                    self.signOut()
                }
            }
        }
    }
}
