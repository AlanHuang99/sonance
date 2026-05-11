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

    private var normalizedServerURL: String {
        let raw = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
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
