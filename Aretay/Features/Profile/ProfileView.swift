//
//  ProfileView.swift
//  Aretay
//
//  Profile sheet, opened from the avatar in the home header: account
//  identity, learner level + memory stats, and sign out.
//

import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var stats = LearnerStats.empty
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(auth.displayName ?? "Learner")
                                .font(.headline)
                            Text("Level \(stats.levelNumber) · \(stats.levelTitle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Stats") {
                    LabeledContent("Day streak") {
                        Text(stats.streakDays == 1 ? "1 day" : "\(stats.streakDays) days")
                    }
                    LabeledContent("Cards in long-term memory") {
                        Text("\(stats.knownCards) of \(stats.trackedCards)")
                    }
                    LabeledContent("Retention (30 days)") {
                        Text(stats.retentionPercent.map { "\($0)%" } ?? "No data")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        Task { await auth.signOut() }
                    }
                    .accessibilityIdentifier("signOutButton")
                }

                if let url = URL(string: "https://aretay.ai/privacy.html") {
                    Section {
                        Link("Privacy Policy", destination: url)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if isDeletingAccount {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Deleting account…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Delete Account", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .accessibilityIdentifier("deleteAccountButton")
                    }
                } footer: {
                    Text("Permanently removes your account and all study data. Cannot be undone.")
                        .font(.caption)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("closeProfile")
                }
            }
            .task(id: auth.sessionLoadID) {
                await reload()
            }
            .refreshable {
                await reload()
            }
            .confirmationDialog(
                "Delete Account",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete My Account and All Data", role: .destructive) {
                    Task { await performDelete() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, all course progress, and your entire review history. There is no undo.")
            }
            .alert("Couldn't Delete Account", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK") { deleteError = nil }
            } message: {
                Text(deleteError ?? "")
            }
        }
    }

    private func performDelete() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        if let error = await auth.deleteAccount() {
            deleteError = error
        }
        // On success, auth.state becomes .signedOut and the app navigates
        // back to SignInView automatically via RootView's state switch.
    }

    private func reload() async {
        #if DEBUG
        if let previewStats = PreviewData.applyLoadedPreviewIfNeeded(
            accessToken: auth.accessToken
        ) {
            stats = previewStats
            return
        }
        #endif
        guard let token = try? await auth.validAccessToken() else { return }
        async let states = StudyAPI.fetchStateRows(accessToken: token)
        async let logs = StudyAPI.fetchRecentLogs(accessToken: token)
        if let states = try? await states, let logs = try? await logs {
            stats = LearnerStats.compute(states: states, logs: logs)
        }
    }
}

#if DEBUG
#Preview("Loaded") {
    ProfileView()
        .environment(AuthManager.preview)
}

#Preview("Empty") {
    ProfileView()
        .environment(AuthManager.previewSignedInEmpty)
}
#endif
