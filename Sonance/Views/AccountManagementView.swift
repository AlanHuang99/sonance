import SwiftUI

struct AccountManagementView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var player: Player
    @EnvironmentObject var favorites: FavoritesStore
    @EnvironmentObject var library: LibraryStore

    @State private var selectedAccountID: ServerAccount.ID?
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var alias = ""
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

                NetworkDiagnosticsPanel()
            }
            .padding(28)
        }
        .contentMargins(.bottom, miniPlayerSafeAreaInset, for: .scrollContent)
        .navigationTitle("Accounts")
        .onAppear(perform: selectInitialAccount)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server Accounts")
                .font(.system(size: 28, weight: .semibold))
            Text("Give servers a nickname, test credentials, choose the startup default, switch accounts, or delete old entries.")
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
                .controlSize(.large)
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
                TextField("Nickname (optional, e.g. Home Server)", text: $alias)
                    .textFieldStyle(.roundedBorder)
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
            .controlSize(.large)

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
                            Text(account.displayName)
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
                        Text(secondaryLine(for: account))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(isActive ? "Active" : relativeLastUsed(account.lastUsedAt))
                            .font(.caption2)
                            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                        if isSelected {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
            .controlSize(.large)
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
        alias = account.alias ?? ""
        statusMessage = nil
        statusIsError = false
    }

    private func clearForm() {
        selectedAccountID = nil
        serverURL = ""
        username = ""
        password = ""
        alias = ""
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
        let prepared = currentCredentials.preparedForConnection
        auth.saveAccount(prepared)
        auth.setAlias(alias, for: prepared.accountID)
        serverURL = prepared.serverURL
        username = prepared.username
        selectedAccountID = prepared.accountID
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
                auth.setAlias(alias, for: currentCredentials.accountID)
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
        library.clear()
    }

    /// When an alias is set the host would otherwise be hidden, so surface it alongside the
    /// username; without an alias the primary line already shows the host.
    private func secondaryLine(for account: ServerAccount) -> String {
        if account.hasAlias {
            return "\(account.credentials.displayHost) · \(account.credentials.username)"
        }
        return account.credentials.username
    }

    private func relativeLastUsed(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
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

/// Read-out of per-endpoint Subsonic request counts. Useful for verifying cache hit rates and
/// pinning down chatty code paths. Counts are process-lifetime — refreshing the snapshot
/// re-reads `NetworkDiagnostics`; `Reset` zeroes the underlying counters.
private struct NetworkDiagnosticsPanel: View {
    @State private var snapshot: [String: Int] = [:]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Counts are cumulative for the current process. Reset clears them in place.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") { snapshot = NetworkDiagnostics.snapshot() }
                    Button("Reset", role: .destructive) {
                        NetworkDiagnostics.reset()
                        snapshot = NetworkDiagnostics.snapshot()
                    }
                }
                if snapshot.isEmpty {
                    Text("No requests recorded yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(snapshot.keys.sorted(), id: \.self) { key in
                            HStack {
                                Text(key).font(.callout.monospaced())
                                Spacer()
                                Text("\(snapshot[key] ?? 0)")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Network Diagnostics", systemImage: "chart.bar.xaxis")
                .font(.headline)
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { snapshot = NetworkDiagnostics.snapshot() }
        .onChange(of: isExpanded) { _, expanded in
            if expanded { snapshot = NetworkDiagnostics.snapshot() }
        }
    }
}
