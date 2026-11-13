import Foundation

class ServerConfig: ObservableObject {
    // MARK: Lifecycle

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
        adminToken = UserDefaults.standard.string(forKey: "adminToken") ?? ""
    }

    // MARK: Internal

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: "serverURL") }
    }

    @Published var adminToken: String {
        didSet {
            // In production, use Keychain instead of UserDefaults
            UserDefaults.standard.set(adminToken, forKey: "adminToken")
        }
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !adminToken.isEmpty
    }

    var baseURL: String {
        let url = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    func disconnect() {
        serverURL = ""
        adminToken = ""
    }
}
