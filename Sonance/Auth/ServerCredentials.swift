import Foundation

struct ServerCredentials: Codable, Equatable {
    var serverURL: String
    var username: String
    var password: String

    var accountID: String {
        "\(normalizedServerURL)|\(username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    var displayHost: String {
        let raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: raw), let host = url.host {
            if let port = url.port { return "\(host):\(port)" }
            return host
        }
        return raw
    }

    var preparedForConnection: ServerCredentials {
        ServerCredentials(
            serverURL: Self.normalizedServerInput(serverURL),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }

    private var normalizedServerURL: String {
        let raw = Self.normalizedServerInput(serverURL)
        guard var components = URLComponents(string: raw) else {
            return raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "" : "/" + path
        components.query = nil
        components.fragment = nil
        return (components.string ?? raw).lowercased()
    }

    private static func normalizedServerInput(_ value: String) -> String {
        var raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return raw }
        if !raw.localizedCaseInsensitiveContains("://") {
            raw = "http://" + raw
        }
        while raw.hasSuffix("/") {
            raw.removeLast()
        }
        if raw.lowercased().hasSuffix("/rest") {
            raw.removeLast(5)
        }
        return raw
    }
}

struct ServerAccount: Codable, Identifiable, Equatable {
    let id: String
    var credentials: ServerCredentials
    var lastUsedAt: Date

    init(credentials: ServerCredentials, lastUsedAt: Date = Date()) {
        self.id = credentials.accountID
        self.credentials = credentials
        self.lastUsedAt = lastUsedAt
    }
}
