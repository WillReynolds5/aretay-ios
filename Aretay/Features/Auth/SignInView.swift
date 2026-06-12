//
//  SignInView.swift
//  Aretay
//
//  Login screen: full-bleed hero background, brand lockup per design spec,
//  and a glass-style Sign in with Apple button.
//

import SwiftUI
import AuthenticationServices

// MARK: - Brand palette (design spec)

private enum Brand {
    static let mark = Color(red: 0xCD / 255, green: 0xD5 / 255, blue: 0xEC / 255)   // #CDD5EC
    static let line1 = Color(red: 0xF5 / 255, green: 0xF2 / 255, blue: 0xEA / 255)  // #F5F2EA
    static let line2 = Color(red: 0xF0 / 255, green: 0xD9 / 255, blue: 0xA8 / 255)  // #F0D9A8
    static let shadow = Color(red: 0x0A / 255, green: 0x0C / 255, blue: 0x1E / 255) // #0A0C1E
}

struct SignInView: View {
    @Environment(AuthManager.self) private var auth
    @State private var appleSignIn = AppleSignInCoordinator()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background(size: proxy.size)

                VStack(spacing: 0) {
                    Spacer(minLength: proxy.size.height * 0.12)

                    BrandLockup(width: proxy.size.width)

                    Spacer()

                    VStack(spacing: 16) {
                        GlassSignInButton {
                            appleSignIn.start(auth: auth)
                        }
                        .accessibilityIdentifier("signInWithAppleButton")

                        if let message = auth.errorMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(Brand.line1.opacity(0.9))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .shadow(color: Brand.shadow.opacity(0.8), radius: 4)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 56)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func background(size: CGSize) -> some View {
        Image("LoginBackground")
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay(
                // Subtle scrim so the button area stays legible over the clouds.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.62),
                        .init(color: Brand.shadow.opacity(0.45), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

// MARK: - Brand lockup (design spec: everything keys off the caps line S)

private struct BrandLockup: View {
    /// Container width; the caps line spans ~80% of it at 0.34em tracking.
    let width: CGFloat

    var body: some View {
        // "BECOME EXTRAORDINARY" rendered at 36px on a 941px canvas → S ≈ 0.038 × width.
        // Scaled up 1.15× so the caps line spans ~92% of the screen; each line
        // auto-shrinks via minimumScaleFactor if it would ever overflow.
        let s = width * (36.0 / 941.0) * 1.15
        let blur = 0.2 * s
        let maxLineWidth = width * 0.93

        VStack(spacing: 0) {
            brandText("aretay", font: "Montserrat-Light", size: 0.63 * s, tracking: 0.45, color: Brand.mark, blur: blur, maxWidth: maxLineWidth)
                .padding(.bottom, 1.15 * s)

            brandText("Learn Anything.", font: "LibreCaslonText-Italic", size: 1.8 * s, tracking: 0, color: Brand.line1, blur: blur, maxWidth: maxLineWidth)
                .padding(.bottom, 0.95 * s)

            brandText("BECOME EXTRAORDINARY", font: "Montserrat-Medium", size: s, tracking: 0.34, color: Brand.line2, blur: blur, maxWidth: maxLineWidth)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aretay. Learn anything. Become extraordinary.")
    }

    /// Crisp text over a blurred legibility-shadow duplicate (spec: #0A0C1E @ 78%, blur 0.2×S).
    private func brandText(
        _ string: String,
        font: String,
        size: CGFloat,
        tracking trackingEm: CGFloat,
        color: Color,
        blur: CGFloat,
        maxWidth: CGFloat
    ) -> some View {
        let tracking = trackingEm * size
        let text = Text(string)
            .font(.custom(font, size: size))
            .tracking(tracking)
            .lineLimit(1)
            .minimumScaleFactor(0.6)

        return ZStack {
            text
                .foregroundStyle(Brand.shadow.opacity(0.78))
                .blur(radius: blur)
            text
                .foregroundStyle(color)
        }
        // .tracking adds a trailing space after the last glyph; nudge to re-center.
        .padding(.leading, tracking)
        .frame(maxWidth: maxWidth)
    }
}

// MARK: - Glass-style Sign in with Apple button

private struct GlassSignInButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "applelogo")
                    .font(.system(size: 19, weight: .medium))
                    .baselineOffset(1)
                Text("Sign in with Apple")
                    .font(.system(size: 19, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

private struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                // Top-lit specular edge.
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.55),
                                .white.opacity(0.12),
                                .white.opacity(0.05),
                                .white.opacity(0.25),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                // Inner glass sheen.
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            }
            .clipShape(Capsule())
            .shadow(color: Brand.shadow.opacity(0.35), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Apple sign-in coordinator (drives AuthManager from a custom button)

@MainActor
@Observable
private final class AppleSignInCoordinator: NSObject {
    private var auth: AuthManager?
    private var controller: ASAuthorizationController?

    func start(auth: AuthManager) {
        self.auth = auth

        let request = ASAuthorizationAppleIDProvider().createRequest()
        auth.prepareAppleRequest(request)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        let auth = self.auth
        controller = nil
        Task { await auth?.handleAppleCompletion(result) }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in self.finish(.success(authorization)) }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in self.finish(.failure(error)) }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

#Preview {
    SignInView()
        .environment(AuthManager(client: SupabaseManager.shared))
}
