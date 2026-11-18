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
                    logOut()
                }
                .foregroundColor(.red)
            }
        }
    }
    
    /// The child token has no expiry and no refresh token. A 401 means the
    /// parent linked a new device (or deleted the account), so the only
    /// thing to do is go back to the start screen.
    func fetchTasks() async {
        isLoading = true
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/today") else { return }
        
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
                } else if httpResponse.statusCode == 401 {
                    logOut()
                }
            }
        } catch {
            print("Error fetching tasks: \(error)")
        }
        isLoading = false
    }
    
    func logOut() {
        KeychainSwift().delete("child_token")
        authTrigger += 1
    }
}
