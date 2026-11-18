//
//  OnboardingView.swift
//  Habito
//
//  The start of the app: choose a role, then either sign up (new parent),
//  log in (parent with an account) or enter the room code (child).
//
//  New parent:  Choose your role → Sign up → Your code → Congratulations → Home
//  Has account: Choose your role → Log in → Home
//

import SwiftUI
import Observation
import KeychainSwift

enum OnboardingRoute: Hashable {
    case signUp, logIn, code, congratulations, child
}

/// What the screens after Sign up need to show.
@Observable
final class OnboardingModel {
    var roomCode = ""
    var childName = ""
}

// MARK: - 1. Start / Onboarding Branch
struct OnboardingView: View {
    @State private var path: [OnboardingRoute] = []
    @State private var model = OnboardingModel()

    var body: some View {
        NavigationStack(path: $path) {
            RoleView(path: $path)
                .navigationDestination(for: OnboardingRoute.self) { route in
                    switch route {
                    case .signUp: AccountView(mode: .signUp, path: $path, model: model)
                    case .logIn: AccountView(mode: .logIn, path: $path, model: model)
                    case .code: CodeView(path: $path, model: model)
                    case .congratulations: CongratulationsView(model: model)
                    case .child: ChildInsertCodeView()
                    }
                }
        }
        .tint(.habitoGreenDeep)
    }
}

// MARK: - 2. Choose your role
private struct RoleView: View {
    @Binding var path: [OnboardingRoute]
    @State private var role: Role = .parent
    @State private var showHelp = false

    enum Role { case child, parent }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Choose your role",
                subtitle: "Select the option which\nbetter describes you"
            )
            .padding(.top, 56)

            HStack(spacing: 24) {
                RoleTile(title: "Child", symbol: "figure.child", isSelected: role == .child) { role = .child }
                RoleTile(title: "Parent", symbol: "figure.and.child.holdinghands", isSelected: role == .parent) { role = .parent }
            }
            .padding(.top, 48)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HabitoBackground())
        .safeAreaInset(edge: .bottom) {
            BottomButton(title: "Confirm") {
                path.append(role == .parent ? .signUp : .child)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StepBar(step: 1) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: { Image(systemName: "questionmark") }
                    .accessibilityLabel("Help")
            }
        }
        .alert("Which one are you?", isPresented: $showHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Parents set tasks and follow their child’s progress. Children join with the room code their parent shows them.")
        }
    }
}

private struct RoleTile: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(isSelected ? Color.habitoGreen : Color.habitoCard)
                        .shadow(
                            color: isSelected ? Color.habitoGreenDeep.opacity(0.22) : .black.opacity(0.08),
                            radius: isSelected ? 11 : 11,
                            y: 8
                        )
                    Image(systemName: symbol)
                        .font(.system(size: 58))
                        .foregroundStyle(isSelected ? Color.black : Color.primary)
                }
                .frame(width: 160, height: 160)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 3. Sign up and Log in
private struct AccountView: View {
    enum Mode { case signUp, logIn }

    let mode: Mode
    @Binding var path: [OnboardingRoute]
    var model: OnboardingModel

    @State private var email = ""
    @State private var password = ""
    @State private var childName = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, childName }

    private var isSignUp: Bool { mode == .signUp }
    private var cleanEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        cleanEmail.contains("@") && (isSignUp ? password.count >= 8 : !password.isEmpty)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    OnboardingHeader(
                        title: isSignUp ? "Create your account" : "Welcome back",
                        subtitle: isSignUp ? "Sign up with your email\nand a password" : "Log in with your email\nand password"
                    )
                    .padding(.top, 56)

                    VStack(alignment: .leading, spacing: 12) {
                        fields
                        footnote
                        switchLink
                    }
                    .id("form")
                    .padding(.horizontal, 20)
                    .padding(.top, 48)
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            // With the keyboard up there is little room: bring the form to the top so the
            // button above the keyboard does not cover its last row.
            .onChange(of: focus) { _, field in
                guard field != nil else { return }
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("form", anchor: .top) }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(HabitoBackground())
        .safeAreaInset(edge: .bottom) {
            BottomButton(title: isSignUp ? "Sign up" : "Log in", isBusy: isBusy) {
                Task { await submit() }
            }
            .disabled(!canSubmit)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSignUp {
                ToolbarItem(placement: .principal) { StepBar(step: 2) }
            }
        }
    }

    // MARK: Pieces

    private var fields: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text("Email").foregroundStyle(.secondary)
                TextField("name@example.com", text: $email)
                    .focused($focus, equals: .email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }
            .frame(minHeight: 52)

            Divider()

            GridRow {
                Text("Password").foregroundStyle(.secondary)
                SecureField(isSignUp ? "8 or more characters" : "Password", text: $password)
                    .focused($focus, equals: .password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .submitLabel(isSignUp ? .next : .go)
                    .onSubmit {
                        if isSignUp { focus = .childName } else { Task { await submit() } }
                    }
            }
            .frame(minHeight: 52)

            if isSignUp {
                Divider()

                GridRow {
                    Text("Child’s name").foregroundStyle(.secondary)
                    TextField("Optional", text: $childName)
                        .focused($focus, equals: .childName)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                }
                .frame(minHeight: 52)
            }
        }
        .font(.body)
        .padding(.horizontal, 16)
        .habitoCard()
    }

    /// The error if there is one; on Sign up the password rule otherwise.
    @ViewBuilder
    private var footnote: some View {
        if let errorText {
            Text(errorText)
                .font(.footnote)
                .foregroundStyle(Color.habitoRed)
                .padding(.horizontal, 16)
        } else if isSignUp {
            Text("At least 8 characters")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    private var switchLink: some View {
        HStack(spacing: 4) {
            Text(isSignUp ? "Already have an account?" : "Don’t have an account?")
                .foregroundStyle(.secondary)
            Button(isSignUp ? "Log in" : "Sign up") {
                path = [isSignUp ? .logIn : .signUp]
            }
            .fontWeight(.semibold)
            .foregroundStyle(Color.habitoGreenDeep)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: Submit

    private func submit() async {
        guard canSubmit, !isBusy else { return }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            switch mode {
            case .signUp:
                let response = try await HabitoAPI.signUp(email: cleanEmail, password: password, childName: childName)
                model.roomCode = response.parent.roomCode
                model.childName = response.parent.childName ?? ""
                path.append(.code)
            case .logIn:
                _ = try await HabitoAPI.logIn(email: cleanEmail, password: password)
                // The login is in the Keychain: let ContentView swap to Home.
                ParentSession.refreshRoot()
            }
        } catch {
            if error.isCancellation { return }
            errorText = error.habitoMessage
        }
    }
}

// MARK: - 4. Parent: [ROOM CODE] Display
private struct CodeView: View {
    @Binding var path: [OnboardingRoute]
    var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(title: "Your code is")
                .padding(.top, 56)

            Spacer()

            Text(model.roomCode)
                .font(.system(size: 46, weight: .bold))
                .tracking(7)
                .padding(.leading, 7) // balances the space after the last letter
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .textSelection(.enabled)
                .accessibilityLabel("Your code is \(model.roomCode.map(String.init).joined(separator: " "))")

            Spacer()

            Text("Enter this code on\nyour child’s device\nto track their progress")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 56)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HabitoBackground())
        .safeAreaInset(edge: .bottom) {
            BottomButton(title: "Confirm") { path.append(.congratulations) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StepBar(step: 3) }
        }
    }
}

// MARK: - 5. Congratulations
private struct CongratulationsView: View {
    var model: OnboardingModel

    private var name: String { model.childName.isEmpty ? "your child" : model.childName }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Congratulations 🎉",
                subtitle: "Now you and \(name)\nare closer than ever"
            )
            .padding(.top, 56)

            Spacer()

            Image(systemName: "figure.stand.line.dotted.figure.stand")
                .font(.system(size: 76))
                .foregroundStyle(.primary)
                .accessibilityHidden(true)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HabitoBackground())
        .safeAreaInset(edge: .bottom) {
            // The login was saved at Sign up; this just lets ContentView swap to Home.
            BottomButton(title: "Confirm") { ParentSession.refreshRoot() }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { StepBar(step: 4) }
        }
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

                    // The child token never expires, so there is no refresh token.
                    // It only stops working if the parent links a new device.
                    KeychainSwift().set(receivedToken, forKey: "child_token")

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
