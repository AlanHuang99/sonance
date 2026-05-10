import Foundation

struct ServerCredentials: Codable, Equatable {
    var serverURL: String
    var username: String
    var password: String
}
