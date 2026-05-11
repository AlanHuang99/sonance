import SwiftUI

struct AccountManagementView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore

    @State private var selectedAccountID: ServerAccount.ID?
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        accountList
                            .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
                        editor
                            .frame(maxWidth: 520)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        accountList
                        editor
                    }
                }
            }
            .padding(28)
        }
        .navigationTitle("Accounts")
        .onAppear(perform: selectInitialAccount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server Accounts")
                .font(.system(size: 28, weight: .semibold))
            Text("Save servers, test credentials, choose the startup test server, switch accounts, or delete old entries.")
                .foregroundStyle(.secondary)
        }
    }

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved")
                    .font(.headline)
                Spacer()
                Button {
                    clearForm()
                } label: {
                    Label("New", systemImage: "plus")
                }
            }

            if auth.savedAccounts.isEmpty {
                ContentUnavailableView("No Saved Accounts", systemImage: "server.rack", description: Text("Save a server to make it available here."))
                    .frame(minHeight: 180)
            } else {
                VStack(spacing: 10) {
                    ForEach(auth.savedAccounts) { account in
                        accountRow(account)
                    }
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedAccountID == nil ? "Add Server" : "Edit Server")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
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

            if let statusMessage {
                Label(statusMessage, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(statusIsError ? .red : .green)
            }

            HStack(spacing: 10) {
                Button {
                    testCurrentForm()
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Test", systemImage: "network")
                    }
                }
                .disabled(!canSubmit || isBusy)

                Button {
                    saveCurrentForm()
                } label: {
                    Label("Save", systemImage: "tray.and.arrow.down")
                }
                .disabled(!canSubmit || isBusy)

                Button {
                    connectCurrentForm()
                } label: {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(auth.isLoggedIn ? "Save & Switch" : "Save & Connect", systemImage: "arrow.right.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isBusy)
            }

            Text("Save keeps the account available for future launches. Test checks the server without switching away from the current account.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func accountRow(_ account: ServerAccount) -> some View {
        let isActive = account.id == auth.activeAccountID
        let isSelected = account.id == selectedAccountID
        let isDefault = account.id == auth.testServerAccountID

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                select(account)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(account.credentials.displayHost)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            if isDefault {
                                Text("Default")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.yellow.opacity(0.22), in: Capsule())
                            }
                        }
                        Text(account.credentials.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "pencil")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button("Switch") {
                    connectSaved(account.id)
                }
                .disabled(isActive || isBusy)

                Button(isDefault ? "Default" : "Make Default") {
                    auth.setTestServerPreset(id: account.id)
                }
                .disabled(isDefault)

                Button("Delete", role: .destructive) {
                    delete(account.id)
                }
                .disabled(isBusy)
            }
            .font(.caption)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }

    private func selectInitialAccount() {
        guard selectedAccountID == nil else { return }
        if let activeID = auth.activeAccountID,
           let active = auth.savedAccounts.first(where: { $0.id == activeID }) {
            select(active)
        } else if let first = auth.savedAccounts.first {
            select(first)
        }
    }

    private func select(_ account: ServerAccount) {
        selectedAccountID = account.id
        serverURL = account.credentials.serverURL
        username = account.credentials.username
        password = account.credentials.password
        statusMessage = nil
        statusIsError = false
    }

    private func clearForm() {
        selectedAccountID = nil
        serverURL = ""
        username = ""
        password = ""
        statusMessage = nil
        statusIsError = false
    }

    private func testCurrentForm() {
        isTesting = true
        statusMessage = nil
        Task {
            let error = await auth.testConnection(currentCredentials)
            statusIsError = error != nil
            statusMessage = error ?? "Connection succeeded."
            isTesting = false
        }
    }

    private func saveCurrentForm() {
        auth.saveAccount(currentCredentials)
        selectedAccountID = currentCredentials.accountID
        statusIsError = false
        statusMessage = "Account saved."
    }

    private func connectCurrentForm() {
        isConnecting = true
        statusMessage = nil
        Task {
            clearPlaybackState()
            await auth.signIn(currentCredentials)
            if let error = auth.lastError {
                statusIsError = true
                statusMessage = error
            } else {
                selectedAccountID = currentCredentials.accountID
                statusIsError = false
                statusMessage = "Connected."
            }
            isConnecting = false
        }
    }

    private func connectSaved(_ id: ServerAccount.ID) {
        isConnecting = true
        Task {
            clearPlaybackState()
            await auth.connectSavedAccount(id: id)
            isConnecting = false
        }
    }

    private func delete(_ id: ServerAccount.ID) {
        auth.forgetAccount(id: id)
        if selectedAccountID == id {
            clearForm()
        }
    }

    private func clearPlaybackState() {
        player.clearQueue()
        favorites.clear()
    }

    private var currentCredentials: ServerCredentials {
        ServerCredentials(serverURL: serverURL, username: username, password: password)
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    private var isBusy: Bool {
        isTesting || isConnecting
    }
}
