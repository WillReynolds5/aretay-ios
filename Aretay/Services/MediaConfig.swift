//
//  MediaConfig.swift
//  Aretay
//
//  Builds public media URLs from R2 object keys (cards.video_r2_key).
//  R2_PUBLIC_BASE_URL comes from Config/Secrets.xcconfig — the bucket's
//  public r2.dev development URL or a custom CDN domain.
//

import Foundation

enum MediaConfig {
    static let publicBaseURL: String = {
        let raw = Bundle.main.object(forInfoDictionaryKey: "R2_PUBLIC_BASE_URL") as? String ?? ""
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }()

    static var isConfigured: Bool {
        !publicBaseURL.isEmpty && !publicBaseURL.contains("your-r2")
    }

    static func publicURL(forKey key: String) -> URL? {
        guard isConfigured else { return nil }
        return URL(string: "\(publicBaseURL)/\(key)")
    }
}
