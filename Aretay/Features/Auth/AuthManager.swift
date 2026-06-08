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
import Supabase

@MainActor
@Observable
final class AuthManager {

    enum State: Equatable {
        case unknown            // initial — waiting for auth stream
        case signedOut
        case signedIn(User)
    }

    private(set) var state: State = .unknown
    var errorMessage: String?

    /// Stable id for SwiftUI `.task(id:)` — avoids reload loops from token refresh events.
    var sessionLoadID: String? {
        switch state {
        case .unknown, .signedOut:
            return nil
        case .signedIn(let user):
            return isDebugSession ? "debug" : user.id.uuidString
        }
    }

    private let client: SupabaseClient
    private var currentNonce: String?
    private var isDebugSession = false

    init(client: SupabaseClient = SupabaseManager.shared) {
        self.client = client
        Task { [weak self] in
            await self?.bootstrapAuth()
        }
    }

    // MARK: - Auth state observation

    private func bootstrapAuth() async {
        // Never block UI on client.auth.session — it can hang on simulator.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.fallbackFromUnknown()
        }
        await observeAuthChanges()
    }

    private func fallbackFromUnknown() {
        guard case .unknown = state, !isDebugSession else { return }
        state = .signedOut
    }

    private func observeAuthChanges() async {
        for await (event, session) in client.auth.authStateChanges {
            apply(event: event, session: session)
        }
    }

    private func apply(event: AuthChangeEvent, session: Session?) {
        if isDebugSession { return }

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
        isDebugSession = false
        switch result {
        case .success(let authorization):
            await exchangeWithSupabase(authorization)
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return
        case .failure(let error):
            errorMessage = error.localizedDescription
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

    // MARK: - Debug bypass (DEBUG builds only)

#if DEBUG
    func debugBypassAuth() {
        errorMessage = nil
        isDebugSession = true
        state = .signedIn(User(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            createdAt: Date(),
            updatedAt: Date()
        ))
    }
#endif

    // MARK: - Sign out

    func signOut() async {
        isDebugSession = false
        do {
            try await client.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        state = .signedOut
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
}
