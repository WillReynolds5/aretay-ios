//
//  AuthManager.swift
//  Aretay
//
//  @Observable auth state holder. Owns the Sign in with Apple → Supabase flow.
//

import Foundation
import Observation
import AuthenticationServices
import CryptoKit
import OSLog
import Supabase

private let authLog = Logger(subsystem: "com.willreynolds.aretay", category: "Auth")

@MainActor
@Observable
final class AuthManager {

    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .unknown
    var errorMessage: String?

    /// Last known access token (may be expired). Prefer ``validAccessToken()`` for API calls.
    private(set) var accessToken: String?

    /// Returns a valid access token, refreshing the Supabase session when needed.
    func validAccessToken() async throws -> String {
#if DEBUG
        if accessToken == PreviewData.previewAccessToken {
            return PreviewData.previewAccessToken
        }
#endif
        let session = try await client.auth.session
        accessToken = session.accessToken
        return session.accessToken
    }

    /// Stable id for SwiftUI `.task(id:)` — avoids reload loops from token refresh events.
    var sessionLoadID: String? {
        switch state {
        case .unknown, .signedOut:
            return nil
        case .signedIn(let user):
            return user.id.uuidString
        }
    }

    /// Supabase auth user id. Nil when signed out.
    var userID: UUID? {
        guard case .signedIn(let user) = state else { return nil }
        return user.id
    }

    /// First name from Sign in with Apple metadata, when available.
    var displayName: String? {
        guard case .signedIn(let user) = state else { return nil }
        for key in ["full_name", "name", "given_name"] {
            if let value = Self.metadataString(user.userMetadata[key]), !value.isEmpty {
                return Self.formattedFirstName(from: value)
            }
        }
        return nil
    }

    private let client: SupabaseClient
    private var currentNonce: String?

    init(client: SupabaseClient = SupabaseManager.shared, observeChanges: Bool = true) {
        self.client = client
        if observeChanges {
            Task { await observeAuthChanges() }
        }
    }

#if DEBUG
    /// Seeds signed-in preview state without touching Supabase.
    func configureForPreview(
        displayName: String = "Alex",
        accessToken: String? = PreviewData.previewAccessToken
    ) {
        let now = Date()
        let user = User(
            id: PreviewData.userID,
            appMetadata: [:],
            userMetadata: ["given_name": .string(displayName)],
            aud: "authenticated",
            createdAt: now,
            updatedAt: now
        )
        self.accessToken = accessToken
        state = .signedIn(user)
    }

    static var preview: AuthManager {
        let auth = AuthManager(client: SupabaseManager.shared, observeChanges: false)
        auth.configureForPreview()
        return auth
    }

    static var previewSignedInEmpty: AuthManager {
        let auth = AuthManager(client: SupabaseManager.shared, observeChanges: false)
        auth.configureForPreview(accessToken: nil)
        return auth
    }
#endif

    // MARK: - Auth state observation

    private func observeAuthChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            apply(event: event, session: session)
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        accessToken = session?.accessToken

        switch event {
        case .signedOut, .userDeleted:
            state = .signedOut
        case .initialSession:
            state = session.map { .signedIn($0.user) } ?? .signedOut
        default:
            if let session {
                state = .signedIn(session.user)
            }
        }
    }

    // MARK: - Sign in with Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        errorMessage = nil
        switch result {
        case .success(let authorization):
            await exchangeWithSupabase(authorization)
        case .failure(let error):
            logAppleFailure(error)
            if let authError = error as? ASAuthorizationError,
               authError.code == .canceled,
               !Self.isLikelyAccountFailure(error) {
                return
            }
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func exchangeWithSupabase(_ authorization: ASAuthorization) async {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8),
            let rawNonce = currentNonce
        else {
            errorMessage = "Apple did not return a valid identity token."
            return
        }

        do {
            try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(
                    provider: .apple,
                    idToken: idToken,
                    nonce: rawNonce
                )
            )
            currentNonce = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func logAppleFailure(_ error: Error) {
        let nsError = error as NSError
        authLog.error("Sign in with Apple failed: \(nsError.domain, privacy: .public) \(nsError.code) \(error.localizedDescription, privacy: .public)")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            authLog.error("Underlying: \(underlying.domain, privacy: .public) \(underlying.code) \(underlying.localizedDescription, privacy: .public)")
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if isLikelyAccountFailure(error) {
            return "Sign in with Apple isn't configured for this build. In Xcode, open the Aretay target → Signing & Capabilities → add Sign in with Apple, then clean build and reinstall on your device."
        }

        if let authError = error as? ASAuthorizationError, authError.code == .unknown {
            return "Sign in with Apple failed. Run on a physical iPhone (not the simulator), stay signed into iCloud in Settings, and use your real Apple ID."
        }

        return error.localizedDescription
    }

    private static func isLikelyAccountFailure(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let nsError = current {
            if nsError.domain == "AKAuthenticationError" {
                switch nsError.code {
                case -7003, -7022, -7026:
                    return true
                default:
                    break
                }
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    // MARK: - Sign out

    func signOut() async {
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        accessToken = nil
        state = .signedOut
    }

    // MARK: - Account deletion

    /// Calls the `delete-account` Edge Function (service-role delete),
    /// then clears local auth state. Returns an error string on failure.
    func deleteAccount() async -> String? {
        let token: String
        do {
            token = try await validAccessToken()
        } catch {
            return "Not signed in."
        }

        let functionURL = SupabaseConfig.url
            .appendingPathComponent("functions/v1/delete-account")

        var request = URLRequest(url: functionURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                authLog.error("delete-account: HTTP \(http.statusCode) — \(body, privacy: .public)")
                return "Server error (\(http.statusCode)). Please try again or contact support."
            }
        } catch {
            authLog.error("delete-account: request failed — \(error.localizedDescription, privacy: .public)")
            return "Could not reach the server. Check your connection and try again."
        }

        // Clear local state regardless — the server record is gone.
        accessToken = nil
        state = .signedOut
        return nil
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func metadataString(_ value: AnyJSON?) -> String? {
        guard let value, case .string(let string) = value else { return nil }
        return string
    }

    private static func formattedFirstName(from fullName: String) -> String {
        fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? fullName
    }
}
