import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Sonance")
                .font(.system(size: 34, weight: .light))
            Text("Connect to your Navidrome server")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                TextField("https://music.example.com", text: $serverURL)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }
            .frame(maxWidth: 360)

            if let err = auth.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            Button(action: submit) {
                if isSubmitting {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Sign in").frame(maxWidth: 120)
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || serverURL.isEmpty || username.isEmpty || password.isEmpty)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        isSubmitting = true
        Task {
            await auth.signIn(ServerCredentials(
                serverURL: serverURL,
                username: username,
                password: password
            ))
            isSubmitting = false
        }
    }
}
