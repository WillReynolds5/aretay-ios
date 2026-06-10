//
//  SupabaseClient.swift
//  Aretay
//
//  Shared Supabase client. URL and anon key are injected at build time from
//  Config/Secrets.xcconfig into Info.plist via INFOPLIST_KEY_* build settings.
//

import Foundation
import Supabase

enum SupabaseConfig {
    static let isConfigured: Bool = {
        let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
        return !url.contains("your-project") && !key.contains("your-anon")
    }()

    static let url: URL = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        return URL(string: raw) ?? URL(string: "https://placeholder.supabase.co")!
    }()

    static let anonKey: String = {
        return Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? "placeholder-key"
    }()
}

enum SupabaseManager {
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static let shared: SupabaseClient = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.anonKey,
        options: SupabaseClientOptions(
            auth: .init(emitLocalSessionAsInitialSession: true),
            global: .init(session: urlSession)
        )
    )
}
