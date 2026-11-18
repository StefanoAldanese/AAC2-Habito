//
//  ParentCreateTaskView.swift
//  Habito - Test NOT final
//
//  Created by Stefano Emanuele Aldanese on 17/11/2026.
//

import SwiftUI
import KeychainSwift

struct ParentCreateTaskView: View {
    // Connect to the app's refresh trigger
    @AppStorage("authTrigger") var authTrigger = 0
    
    @State private var taskTitle = ""
    @State private var statusMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Assign a Task")
                .font(.title2).bold()
            
            TextField("Task Title (e.g. Make the bed)", text: $taskTitle)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button("Create Task") {
                Task { await createTask() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(taskTitle.isEmpty)
            
            Text(statusMessage)
                .foregroundColor(.gray)
                .font(.footnote)
            
            Spacer()
        }
        .padding()
        .navigationTitle("Parent Tasks")
        // Add the Log Out button to the top right
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Log Out") {
                    Task {
                        await ParentAuth.logout() // revokes the refresh token, clears both tokens
                        authTrigger += 1 // Force the app to redraw and show Onboarding
                    }
                }
                .foregroundColor(.red)
            }
        }
    }
    
    func createTask() async {
        guard let url = URL(string: "\(ParentAuth.baseURL)/tasks") else { return }
        let body = try? JSONSerialization.data(withJSONObject: ["title": taskTitle, "repeat": "once"])
        
        do {
            // ParentAuth.send refreshes the access token once on a 401 and retries.
            guard let (data, httpResponse) = try await ParentAuth.send({ token in
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = body
                return request
            }) else {
                // No usable token: the refresh token expired or was revoked.
                ParentAuth.clearLocal()
                authTrigger += 1
                return
            }
            
            if httpResponse.statusCode == 201 {
                statusMessage = "Task created successfully!"
                taskTitle = "" // clear field
            } else {
                // FOR DEBUG: This will display the error code and message from Django
                let serverError = String(data: data, encoding: .utf8) ?? "Unknown error"
                statusMessage = "Error \(httpResponse.statusCode): \(serverError)"
                print("Backend Error: \(serverError)")
            }
        } catch {
            statusMessage = "Network error: \(error.localizedDescription)"
        }
    }
}
