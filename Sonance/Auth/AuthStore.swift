import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var credentials: ServerCredentials?
    @Published private(set) var client: SubsonicClient?
    @Published private(set) var savedAccounts: [ServerAccount] = []
    @Published private(set) var testServerAccountID: String?
    @Published var lastError: String?
    @Published var isRestoringSession: Bool = false

    var isLoggedIn: Bool { client != nil }
    var activeAccountID: String? { credentials?.accountID }

    private static let legacyStorageKey = "sonance.credentials"
    private static let accountsStorageKey = "sonance.accounts"
    private static let activeAccountKey = "sonance.activeAccountID"
    private static let testServerAccountKey = "sonance.testServerAccountID"
    private static let didUserSignOutKey = "sonance.didUserSignOut"

    #if DEBUG
    static let bundledTestCredentials = ServerCredentials(
        serverURL: "http://alan-mint:2333",
        username: "test",
        password: "test123"
    )
    #endif

    init() {
        self.savedAccounts = Self.loadAccounts()
        self.testServerAccountID = Self.loadTestServerAccountID(from: savedAccounts)
        if !UserDefaults.standard.bool(forKey: Self.didUserSignOutKey),
           let account = Self.loadStartupAccount(from: savedAccounts, testServerAccountID: testServerAccountID) {
            self.credentials = account.credentials
            self.client = SubsonicClient(credentials: account.credentials)
        }
    }

    var testServerAccount: ServerAccount? {
        guard let testServerAccountID else { return nil }
        return savedAccounts.first(where: { $0.id == testServerAccountID })
    }

    func signIn(_ creds: ServerCredentials) async {
        let creds = creds.preparedForConnection
        let candidate = SubsonicClient(credentials: creds)
        do {
            try await candidate.ping()
            self.credentials = creds
            self.client = candidate
            self.lastError = nil
            UserDefaults.standard.removeObject(forKey: Self.didUserSignOutKey)
            upsertAccount(creds)
        } catch let error as SubsonicError {
            self.lastError = error.message
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func testConnection(_ creds: ServerCredentials) async -> String? {
        let creds = creds.preparedForConnection
        let candidate = SubsonicClient(credentials: creds)
        do {
            try await candidate.ping()
            return nil
        } catch let error as SubsonicError {
            return error.message
        } catch {
            return error.localizedDescription
        }
    }

    func saveAccount(_ creds: ServerCredentials) {
        upsertAccount(creds.preparedForConnection)
        lastError = nil
    }

    func connectSavedAccount(id: ServerAccount.ID) async {
        guard let account = savedAccounts.first(where: { $0.id == id }) else { return }
        await signIn(account.credentials)
    }

    func switchToAccount(id: ServerAccount.ID) {
        guard let account = savedAccounts.first(where: { $0.id == id }) else { return }
        credentials = account.credentials
        client = SubsonicClient(credentials: account.credentials)
        lastError = nil
        UserDefaults.standard.removeObject(forKey: Self.didUserSignOutKey)
        markActive(account.id)
    }

    func reconnectTestServer() async {
        guard let account = testServerAccount else { return }
        await signIn(account.credentials)
    }

    func setTestServerPreset(id: ServerAccount.ID) {
        guard savedAccounts.contains(where: { $0.id == id }) else { return }
        testServerAccountID = id
        UserDefaults.standard.set(id, forKey: Self.testServerAccountKey)
        lastError = nil
    }

    func clearTestServerPreset() {
        testServerAccountID = nil
        UserDefaults.standard.removeObject(forKey: Self.testServerAccountKey)
    }

    func signOut(forgetCurrentAccount: Bool = false) {
        let currentID = credentials?.accountID
        if forgetCurrentAccount, let currentID {
            savedAccounts.removeAll { $0.id == currentID }
            if testServerAccountID == currentID {
                clearTestServerPreset()
            }
            Self.saveAccounts(savedAccounts)
        }
        credentials = nil
        client = nil
        UserDefaults.standard.set(true, forKey: Self.didUserSignOutKey)
        UserDefaults.standard.removeObject(forKey: Self.activeAccountKey)
    }

    func forgetAccount(id: ServerAccount.ID) {
        savedAccounts.removeAll { $0.id == id }
        if testServerAccountID == id {
            clearTestServerPreset()
        }
        Self.saveAccounts(savedAccounts)
        if credentials?.accountID == id {
            signOut()
        }
    }

    func restoreLastSavedSessionIfPossible() async {
        guard !isLoggedIn, !isRestoringSession else { return }
        guard !UserDefaults.standard.bool(forKey: Self.didUserSignOutKey) else { return }
        guard let creds = Self.loadStartupAccount(from: savedAccounts, testServerAccountID: testServerAccountID)?.credentials else { return }

        isRestoringSession = true
        defer { isRestoringSession = false }
        await signIn(creds)
    }

    private func upsertAccount(_ creds: ServerCredentials) {
        let account = ServerAccount(credentials: creds)
        savedAccounts.removeAll { $0.id == account.id }
        savedAccounts.insert(account, at: 0)
        Self.saveAccounts(savedAccounts)
        markActive(account.id)
    }

    private func markActive(_ id: String) {
        UserDefaults.standard.set(id, forKey: Self.activeAccountKey)
        if let index = savedAccounts.firstIndex(where: { $0.id == id }) {
            savedAccounts[index].lastUsedAt = Date()
            savedAccounts.sort { $0.lastUsedAt > $1.lastUsedAt }
            Self.saveAccounts(savedAccounts)
        }
    }

    private static func loadAccounts() -> [ServerAccount] {
        #if DEBUG
        if let data = UserDefaults.standard.data(forKey: accountsStorageKey),
           let accounts = try? JSONDecoder().decode([ServerAccount].self, from: data) {
            return ensureBundledTestAccount(in: accounts)
        }

        return ensureBundledTestAccount(in: [])
        #else
        if let data = KeychainHelper.load(account: accountsStorageKey),
           let accounts = try? JSONDecoder().decode([ServerAccount].self, from: data) {
            return accounts.sorted { $0.lastUsedAt > $1.lastUsedAt }
        }

        // One-shot migration from prior UserDefaults storage.
        if let oldData = KeychainHelper.load(account: legacyStorageKey),
           let creds = try? JSONDecoder().decode(ServerCredentials.self, from: oldData) {
            let accounts = [ServerAccount(credentials: creds)]
            saveAccounts(accounts)
            KeychainHelper.delete(account: legacyStorageKey)
            return accounts
        }
        if let oldData = UserDefaults.standard.data(forKey: legacyStorageKey),
           let creds = try? JSONDecoder().decode(ServerCredentials.self, from: oldData) {
            let accounts = [ServerAccount(credentials: creds)]
            saveAccounts(accounts)
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            return accounts
        }
        return []
        #endif
    }

    private static func loadTestServerAccountID(from accounts: [ServerAccount]) -> String? {
        guard let testID = UserDefaults.standard.string(forKey: testServerAccountKey),
              accounts.contains(where: { $0.id == testID }) else {
            if UserDefaults.standard.string(forKey: testServerAccountKey) != nil {
                UserDefaults.standard.removeObject(forKey: testServerAccountKey)
            }
            return nil
        }
        return testID
    }

    private static func loadStartupAccount(from accounts: [ServerAccount], testServerAccountID: String?) -> ServerAccount? {
        if let testID = testServerAccountID,
           let testAccount = accounts.first(where: { $0.id == testID }) {
            return testAccount
        }
        if let activeID = UserDefaults.standard.string(forKey: activeAccountKey),
           let active = accounts.first(where: { $0.id == activeID }) {
            return active
        }
        return accounts.first
    }

    private static func saveAccounts(_ accounts: [ServerAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        #if DEBUG
        UserDefaults.standard.set(data, forKey: accountsStorageKey)
        #else
        _ = KeychainHelper.save(account: accountsStorageKey, data: data)
        #endif
    }

    #if DEBUG
    private static func ensureBundledTestAccount(in accounts: [ServerAccount]) -> [ServerAccount] {
        var result = accounts
        let testAccount = ServerAccount(credentials: bundledTestCredentials)
        if let index = result.firstIndex(where: { $0.id == testAccount.id }) {
            result[index].credentials = bundledTestCredentials
        } else {
            result.insert(testAccount, at: 0)
        }
        if UserDefaults.standard.string(forKey: testServerAccountKey) == nil {
            UserDefaults.standard.set(testAccount.id, forKey: testServerAccountKey)
        }
        saveAccounts(result)
        return result.sorted { $0.lastUsedAt > $1.lastUsedAt }
    }
    #endif
}
