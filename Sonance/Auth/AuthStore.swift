import Foundation
import SwiftUI

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var credentials: ServerCredentials?
    @Published private(set) var client: SubsonicClient?
    @Published var lastError: String?

    var isLoggedIn: Bool { client != nil }

    private static let storageKey = "sonance.credentials"

    init() {
        if let creds = Self.load() {
            self.credentials = creds
            self.client = SubsonicClient(credentials: creds)
        }
    }

    func signIn(_ creds: ServerCredentials) async {
        let candidate = SubsonicClient(credentials: creds)
        do {
            try await candidate.ping()
            self.credentials = creds
            self.client = candidate
            self.lastError = nil
            Self.save(creds)
        } catch let error as SubsonicError {
            self.lastError = error.message
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func signOut() {
        credentials = nil
        client = nil
        KeychainHelper.delete(account: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private static func load() -> ServerCredentials? {
        if let data = KeychainHelper.load(account: storageKey),
           let creds = try? JSONDecoder().decode(ServerCredentials.self, from: data) {
            return creds
        }
        // One-shot migration from prior UserDefaults storage.
        if let oldData = UserDefaults.standard.data(forKey: storageKey),
           let creds = try? JSONDecoder().decode(ServerCredentials.self, from: oldData) {
            _ = KeychainHelper.save(account: storageKey, data: oldData)
            UserDefaults.standard.removeObject(forKey: storageKey)
            return creds
        }
        return nil
    }

    private static func save(_ creds: ServerCredentials) {
        guard let data = try? JSONEncoder().encode(creds) else { return }
        _ = KeychainHelper.save(account: storageKey, data: data)
    }
}
