import Foundation

/// Platform-specific POTA authentication.
/// iOS uses WKWebView; macOS uses ASWebAuthenticationSession.
public protocol POTAAuthProvider: Sendable {
    func authenticate(username: String, password: String) async throws -> String
    func refreshToken() async throws -> String
}
