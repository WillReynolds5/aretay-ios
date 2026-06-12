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
        }
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
        guard let token = auth.accessToken else { return }
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
