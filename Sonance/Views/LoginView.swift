import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    #if DEBUG
    @State private var serverURL = AuthStore.bundledTestCredentials.serverURL
    @State private var username = AuthStore.bundledTestCredentials.username
    @State private var password = AuthStore.bundledTestCredentials.password
    #else
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    #endif
    @State private var isSubmitting = false
    @State private var hasTriedRestore = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sonance")
                            .font(.system(size: 34, weight: .light))
                        Text("Connect to a Navidrome or Subsonic server")
                            .foregroundStyle(.secondary)
                    }

                    if let testServer = auth.testServerAccount {
                        Button(action: reconnectTestServer) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Re-connect Test Server")
                                    .lineLimit(1)
                                Spacer()
                                Text(testServer.credentials.displayHost)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: 360)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                    }

                    if !auth.savedAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved Accounts")
                                .font(.headline)
                            ForEach(auth.savedAccounts) { account in
                                SavedAccountRow(account: account, presetID: auth.testServerAccountID) { id in
                                    toggleTestServerPreset(id)
                                } onSelect: {
                                    auth.switchToAccount(id: account.id)
                                } onForget: {
                                    auth.forgetAccount(id: account.id)
                                }
                            }
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add Server")
                            .font(.headline)
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
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 360, alignment: .leading)
                    }

                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Connect").frame(maxWidth: 120)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || serverURL.isEmpty || username.isEmpty || password.isEmpty)
                }
                .padding(44)
            }
            .task {
                if !hasTriedRestore {
                    hasTriedRestore = true
                    await auth.restoreLastSavedSessionIfPossible()
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct SavedAccountRow: View {
        let account: ServerAccount
        let presetID: String?
        let onSetPreset: (ServerAccount.ID) -> Void
        let onSelect: () -> Void
        let onForget: () -> Void

        var body: some View {
            let isPreset = presetID == account.id
            let presetImage = isPreset ? "pin.fill" : "pin"
            let presetStyle = isPreset ? Color.yellow : Color(nsColor: .tertiaryLabelColor)
            let presetHelp = isPreset ? "Unset test server" : "Set as test server"

            HStack(spacing: 10) {
                Button(action: onSelect) {
                    HStack(spacing: 10) {
                        Image(systemName: "server.rack")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.credentials.displayHost)
                                .lineLimit(1)
                            Text(account.credentials.username)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if isPreset {
                                Text("Default test server")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onForget) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Forget this account")

                Button {
                    onSetPreset(account.id)
                } label: {
                    Image(systemName: presetImage)
                        .foregroundStyle(presetStyle)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help(presetHelp)
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
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

    private func reconnectTestServer() {
        isSubmitting = true
        Task {
            await auth.reconnectTestServer()
            isSubmitting = false
        }
    }

    private func toggleTestServerPreset(_ id: ServerAccount.ID) {
        if auth.testServerAccountID == id {
            auth.clearTestServerPreset()
        } else {
            auth.setTestServerPreset(id: id)
        }
    }

    private var isBusy: Bool {
        isSubmitting || auth.isRestoringSession
    }
}
