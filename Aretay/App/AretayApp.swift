//
//  AretayApp.swift
//  Aretay
//

import SwiftUI
import SwiftData

@main
struct AretayApp: App {
    @State private var auth = AuthManager()
    @State private var courseStore = CourseStore()

    let modelContainer: ModelContainer = {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(auth)
                .environment(courseStore)
                .animation(.default, value: auth.state)
        }
        .modelContainer(modelContainer)
    }
}
