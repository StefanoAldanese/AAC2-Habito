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
    // Connect to the app's refresh trigger
    @AppStorage("authTrigger") var authTrigger = 0
    
    var token: String
    @State private var tasks: [ChildTask] = []
    @State private var isLoading = false
    
    var body: some View {
        VStack {            
            List {
                if tasks.isEmpty {
                    Text("No tasks for today! 🎉")
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                        .listRowSeparator(.hidden)
                } else {
                    // Loop through the tasks if they exist
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
                // This trigger when the user swipes down to reaload the most recently added tasks
                await fetchTasks()
            }
        }
        .task {
            // This runs once when the screen first opens
            await fetchTasks()
        }
        .navigationTitle("Today's Tasks") // Moves the title to the top bar
        .navigationBarTitleDisplayMode(.large)
        // Add the Log Out button to the top right
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Log Out") {
                    KeychainSwift().delete("child_token") // Delete the token
                    authTrigger += 1 // Force the app to redraw
                }
                .foregroundColor(.red)
            }
        }
    }
    
    func fetchTasks() async {
        isLoading = true
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/today") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Fetch the most up-to-date JSON from the database
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let decoded = try JSONDecoder().decode(TodayResponse.self, from: data)
                self.tasks = decoded.tasks
            }
        } catch {
            print("Error fetching tasks: \(error)")
        }
        isLoading = false
    }
}
