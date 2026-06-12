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
    @State private var isTesting = false
    @State private var hasTriedRestore = false
    @State private var selectedAccountID: ServerAccount.ID?
    @State private var statusMessage: String?
    @State private var statusIsError = false

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
                                Text(testServer.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: 360)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(isBusy)
                    }

                    if !auth.savedAccounts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Saved Servers")
                                .font(.headline)
                            ForEach(auth.savedAccounts) { account in
                                SavedAccountRow(account: account, presetID: auth.testServerAccountID) { id in
                                    toggleTestServerPreset(id)
                                } onEdit: {
                                    load(account)
                                } onConnect: {
                                    connectSaved(account.id)
                                } onForget: {
                                    auth.forgetAccount(id: account.id)
                                }
                            }
                        }
                        .frame(maxWidth: 360, alignment: .leading)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedAccountID == nil ? "Add Server" : "Edit Server")
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
                    .controlSize(.large)
                    .frame(maxWidth: 360)

                    if let err = auth.lastError {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 360, alignment: .leading)
                    }

                    if let statusMessage {
                        Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(statusIsError ? .red : .green)
                            .font(.callout)
                            .frame(maxWidth: 360, alignment: .leading)
                    }

                    HStack(spacing: 10) {
                        Button(action: testForm) {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Test", systemImage: "network")
                            }
                        }
                        .disabled(isBusy || !canSubmit)

                        Button(action: saveForm) {
                            Label("Save", systemImage: "tray.and.arrow.down")
                        }
                        .disabled(isBusy || !canSubmit)

                        Button(action: submit) {
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Connect", systemImage: "arrow.right.circle")
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy || !canSubmit)
                    }
                    .controlSize(.large)
                    .frame(maxWidth: 360, alignment: .leading)
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
        let onEdit: () -> Void
        let onConnect: () -> Void
        let onForget: () -> Void

        var body: some View {
            let isPreset = presetID == account.id

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(account.displayName)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if isPreset {
                                Text("Default")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.yellow.opacity(0.22), in: Capsule())
                            }
                        }
                        Text(account.hasAlias
                             ? "\(account.credentials.displayHost) · \(account.credentials.username)"
                             : account.credentials.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Button("Connect", action: onConnect)
                    Button("Edit", action: onEdit)

                    Button(isPreset ? "Default" : "Make Default") {
                        onSetPreset(account.id)
                    }
                    .disabled(isPreset)

                    Button("Delete", role: .destructive, action: onForget)
                }
                .controlSize(.large)
            }
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func submit() {
        isSubmitting = true
        statusMessage = nil
        Task {
            await auth.signIn(currentCredentials)
            if let error = auth.lastError {
                statusIsError = true
                statusMessage = error
            }
            isSubmitting = false
        }
    }

    private func testForm() {
        isTesting = true
        statusMessage = nil
        Task {
            let error = await auth.testConnection(currentCredentials)
            statusIsError = error != nil
            statusMessage = error ?? "Connection succeeded."
            isTesting = false
        }
    }

    private func saveForm() {
        let prepared = currentCredentials.preparedForConnection
        auth.saveAccount(prepared)
        serverURL = prepared.serverURL
        username = prepared.username
        selectedAccountID = prepared.accountID
        statusIsError = false
        statusMessage = "Server saved."
    }

    private func load(_ account: ServerAccount) {
        selectedAccountID = account.id
        serverURL = account.credentials.serverURL
        username = account.credentials.username
        password = account.credentials.password
        statusMessage = nil
        statusIsError = false
    }

    private func connectSaved(_ id: ServerAccount.ID) {
        isSubmitting = true
        statusMessage = nil
        Task {
            await auth.connectSavedAccount(id: id)
            if let error = auth.lastError {
                statusIsError = true
                statusMessage = error
            }
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
        isSubmitting || isTesting || auth.isRestoringSession
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private var currentCredentials: ServerCredentials {
        ServerCredentials(serverURL: serverURL, username: username, password: password)
    }
}
