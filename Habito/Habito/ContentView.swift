//
//  ContentView.swift
//  Habito
//
//  Created by Stefano Emanuele Aldanese on 17/11/2026.
//

import SwiftUI
import KeychainSwift

struct ContentView: View {
    // This view will listen for the trigger
    @AppStorage("authTrigger") var authTrigger = 0
    
    var body: some View {
        // 1. Check if a child is logged in
        if let childToken = KeychainSwift().get("child_token") {
            NavigationStack {
                ChildTaskView(token: childToken)
            }
            
        // 2. Check if a parent is logged in
        } else if KeychainSwift().get("parent_access") != nil {
            NavigationStack {
                ParentCreateTaskView()
            }
            
        // 3. If nobody is logged in, show the Start screen
        } else {
            OnboardingView()
        }
    }
}
