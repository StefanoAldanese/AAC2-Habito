//
//  ParentAuth.swift
//  Habito
//
//  Parent token handling shared by every parent screen.
//
//  The backend issues a short-lived access token (15 minutes) and a
//  refresh token (90 days). Every call to /auth/refresh returns a NEW pair
//  and kills the old refresh token, so both must be stored each time.
//

import Foundation
import KeychainSwift

enum ParentAuth {
    /// The live server. A HABITO_API_URL environment variable (set by the test
    /// scripts, never in a shipped build) points the parent screens at a local one.
    static let baseURL = ProcessInfo.processInfo.environment["HABITO_API_URL"]
        ?? "https://bokijonow.pythonanywhere.com/api/v1"

    static let accessKey = "parent_access"
    static let refreshKey = "parent_refresh"

    static var accessToken: String? { KeychainSwift().get(accessKey) }

    /// Trades the stored refresh token for a new access + refresh pair.
    /// Returns false when the refresh token is missing, expired or revoked,
    /// in which case the parent has to log in again.
    static func refreshTokens() async -> Bool {
        let keychain = KeychainSwift()
        guard let refreshToken = keychain.get(refreshKey),
              let url = URL(string: "\(baseURL)/auth/refresh") else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh": refreshToken])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccess = json["access"] as? String,
                  let newRefresh = json["refresh"] as? String else { return false }
            keychain.set(newAccess, forKey: accessKey)
            keychain.set(newRefresh, forKey: refreshKey)
            return true
        } catch {
            print("Token refresh failed: \(error)")
            return false
        }
    }

    /// Sends an authenticated request. On a 401 it refreshes the tokens once
    /// and retries. Returns nil when the parent must log in again.
    static func send(_ makeRequest: (String) -> URLRequest) async throws -> (Data, HTTPURLResponse)? {
        guard let token = accessToken else { return nil }
        let (data, response) = try await URLSession.shared.data(for: makeRequest(token))
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode != 401 { return (data, http) }

        guard await refreshTokens(), let fresh = accessToken else { return nil }
        let (retryData, retryResponse) = try await URLSession.shared.data(for: makeRequest(fresh))
        guard let retryHttp = retryResponse as? HTTPURLResponse else { return nil }
        return (retryData, retryHttp)
    }

    /// Tells the server to revoke the refresh token, then clears the Keychain.
    /// The local clear happens even if the network call fails.
    static func logout() async {
        let keychain = KeychainSwift()
        if let refreshToken = keychain.get(refreshKey),
           let access = keychain.get(accessKey),
           let url = URL(string: "\(baseURL)/auth/logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh": refreshToken])
            _ = try? await URLSession.shared.data(for: request)
        }
        clearLocal()
    }

    static func clearLocal() {
        let keychain = KeychainSwift()
        keychain.delete(accessKey)
        keychain.delete(refreshKey)
    }
}
