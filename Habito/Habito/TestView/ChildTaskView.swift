//
//  ChildTaskView.swift
//  Habito - Test NOT final
//
//  Created by Stefano Emanuele Aldanese on 17/11/2026.
//

import SwiftUI
import KeychainSwift

// Data models to match the backend JSON structure
struct TodayResponse: Codable {
    let date: String
    let tasks: [ChildTask]
}

struct ChildTask: Identifiable, Codable {
    let id: String
    let title: String
    let status: String
}

// The UI View
struct ChildTaskView: View {
    @AppStorage("authTrigger") var authTrigger = 0
    
    var token: String
    @State private var tasks: [ChildTask] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            List {
                if tasks.isEmpty {
                    Text("No tasks for today!")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(tasks) { task in
                        HStack {
                            Text(task.title)
                            Spacer()
                            if task.status == "done" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await fetchTasks()
            }
        }
        .task {
            await fetchTasks()
        }
        .navigationTitle("Today's Tasks")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Log Out") {
                    KeychainSwift().delete("child_token")
                    KeychainSwift().delete("child_refresh") // <-- Clear refresh token on logout
                    authTrigger += 1
                }
                .foregroundColor(.red)
            }
        }
    }
    
    func fetchTasks() async {
        isLoading = true
        let success = await performFetch()
        
        // If performFetch returned false, it means we got a 401 Expired error
        if !success {
            let refreshed = await refreshAccessToken()
            
            if refreshed {
                // The token was updated! Retry the fetch silently.
                let _ = await performFetch()
            } else {
                // The refresh token is ALSO dead. Force a logout.
                KeychainSwift().delete("child_token")
                KeychainSwift().delete("child_refresh")
                authTrigger += 1
            }
        }
        isLoading = false
    }
    
    func performFetch() async -> Bool {
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/today") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        // Always grab the freshest token directly from the Keychain
        let currentToken = KeychainSwift().get("child_token") ?? token
        request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(TodayResponse.self, from: data)
                    self.tasks = decoded.tasks
                    return true
                } else if httpResponse.statusCode == 401 {
                    return false
                }
            }
        } catch {
            print("Error fetching tasks: \(error)")
        }
        return true
    }
    
    func refreshAccessToken() async -> Bool {
        guard let refreshToken = KeychainSwift().get("child_refresh") else { return false }
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/auth/refresh/") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["refresh": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let newAccess = json["access"] as? String {
                    KeychainSwift().set(newAccess, forKey: "child_token")
                    return true
                }
            }
        } catch {
            print("Failed to refresh token: \(error)")
        }
        return false
    }
}
