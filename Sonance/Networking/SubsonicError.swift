import Foundation

struct SubsonicError: LocalizedError {
    let code: Int
    let message: String
    var errorDescription: String? { message }
}
