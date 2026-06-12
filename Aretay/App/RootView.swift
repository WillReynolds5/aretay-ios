//
//  RootView.swift
//  Aretay
//
//  Routes to the right screen based on the current auth state.
//

import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var auth

    var body: some View {
        switch auth.state {
        case .unknown:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Starting…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            SignInView()
                .transition(.opacity)
        case .signedIn:
            CoursesHomeView()
                .transition(.opacity)
        }
    }
}
