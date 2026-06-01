import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var isCreatingAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                }

                if let errorMessage = auth.errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(isCreatingAccount ? "Create Account" : "Sign In") {
                        Task {
                            if isCreatingAccount {
                                await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    }
                    .disabled(email.isEmpty || password.count < 8)

                    Button(isCreatingAccount ? "Have an account? Sign in" : "Need an account? Sign up") {
                        isCreatingAccount.toggle()
                    }
                }
            }
            .navigationTitle("Budget Tracker")
        }
    }
}
