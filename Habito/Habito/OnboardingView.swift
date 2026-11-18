import SwiftUI
import KeychainSwift

// MARK: - 1. Start / Onboarding Branch
struct OnboardingView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Welcome to Habito")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.bottom, 20)
                
                Text("Parents")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                NavigationLink(destination: ParentRegistrationView()) {
                    Text("Create Parent Account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                
                NavigationLink(destination: ParentLoginView()) {
                    Text("Log In as Parent")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
                
                Divider().padding(.vertical, 10)
                
                Text("Children")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                NavigationLink(destination: ChildInsertCodeView()) {
                    Text("I am a Child")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(40)
        }
    }
}

// MARK: 2.1. Parent Log In
struct ParentLoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoggedIn = false
    @State private var fetchedRoomCode = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome Back")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("Email Address", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            Button(action: {
                Task {
                    await loginWithBackend()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                } else {
                    Text("Log In")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .navigationDestination(isPresented: $isLoggedIn) {
                ParentCodeDisplayView(roomCode: fetchedRoomCode)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Log In")
    }
    
    func loginWithBackend() async {
        isLoading = true
        errorMessage = ""
        
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/auth/login") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyParams)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let parentDict = json["parent"] as? [String: Any],
                       let existingRoomCode = parentDict["room_code"] as? String,
                       let accessToken = json["access"] as? String {
                        
                        KeychainSwift().set(accessToken, forKey: "parent_access")
                        self.fetchedRoomCode = existingRoomCode
                        self.isLoggedIn = true
                    } else {
                        errorMessage = "Failed to parse response."
                    }
                } else {
                    let serverError = String(data: data, encoding: .utf8) ?? "Unknown error"
                    errorMessage = "Error \(httpResponse.statusCode): \(serverError)"
                }
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - 2.2. Parent Registration
struct ParentRegistrationView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isRegistered = false
    @State private var fetchedRoomCode = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Parent Account")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("Email Address", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
            }
            
            Button(action: {
                Task {
                    await registerWithBackend()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(12)
                } else {
                    Text("Register")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .navigationDestination(isPresented: $isRegistered) {
                ParentCodeDisplayView(roomCode: fetchedRoomCode)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Registration")
    }
    
    func registerWithBackend() async {
        isLoading = true
        errorMessage = ""
        
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/auth/register") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyParams: [String: String] = [
            "email": email,
            "password": password,
            "timezone": TimeZone.current.identifier
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyParams)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from server"
                isLoading = false
                return
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let parentDict = json["parent"] as? [String: Any],
                   let newRoomCode = parentDict["room_code"] as? String,
                   let accessToken = json["access"] as? String {
                    
                    // Using KeychainSwift to save the [ROOM CODE], so they dont have to insert it again
                    KeychainSwift().set(accessToken, forKey: "parent_access")
                    self.fetchedRoomCode = newRoomCode
                    self.isRegistered = true
                } else {
                    errorMessage = "Failed to parse response."
                }
            } else {
                let serverError = String(data: data, encoding: .utf8) ?? "Unknown error"
                errorMessage = "Error \(httpResponse.statusCode): \(serverError)"
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// MARK: - 3. Parent: [ROOM CODE] Display
struct ParentCodeDisplayView: View {
    var roomCode: String
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Your Family Room Code")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(roomCode)
                .font(.system(size: 50, weight: .black, design: .monospaced))
                .tracking(5)
                .padding()
                .background(Color.gray.opacity(0.15))
                .cornerRadius(15)
            
            Text("Enter this code on your child's device to link their account to yours.")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
            
            NavigationLink(destination: ParentCreateTaskView()) {
                Text("Continue to Tasks")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
        .padding()
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - 4. Child: Insert [ROOM CODE]
struct ChildInsertCodeView: View {
    @State private var roomCode = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var isJoined = false
    @State private var childToken = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Join Your Family")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Ask your parent for the Room Code.")
                .foregroundColor(.gray)
            
            TextField("Enter Code", text: $roomCode)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.title)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                Task {
                    await joinFamilyRoom()
                }
            }) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                } else {
                    Text("Join")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .disabled(isLoading || roomCode.isEmpty)
            .navigationDestination(isPresented: $isJoined) {
                ChildTaskView(token: childToken)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Child Setup")
    }
    
    func joinFamilyRoom() async {
        isLoading = true
        errorMessage = ""
        
        guard let url = URL(string: "https://bokijonow.pythonanywhere.com/api/v1/join") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let bodyParams: [String: String] = [
            "code": roomCode
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyParams)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Invalid response from server"
                isLoading = false
                return
            }
            
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let receivedToken = json["child_token"] as? String {
                    
                    // Using KeychainSwift to save the [ROOM CODE], so they dont have to insert it again
                    let keychain = KeychainSwift()
                    keychain.set(receivedToken, forKey: "child_token")
                    
                    self.childToken = receivedToken
                    self.isJoined = true
                } else {
                    errorMessage = "Failed to parse child token from response."
                }
            } else {
                let serverError = String(data: data, encoding: .utf8) ?? "Unknown error"
                errorMessage = "Error \(httpResponse.statusCode): \(serverError)"
            }
        } catch {
            errorMessage = "Network error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}


#Preview {
    OnboardingView()
}
