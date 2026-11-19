import Foundation
import Security

/// A Firebase anonymous identity is retained in Keychain, independently of
/// local chat history. Losing authentication must never silently reset quota.
actor AnonymousAIIdentity {
    static let shared = AnonymousAIIdentity()
    private var cached: (token: String, expires: Date)?
    private var pending: Task<String, Error>?
    private let service = "tengely.ai.anonymous.refresh.v1"

    func token() async throws -> String {
        if let cached, cached.expires > Date().addingTimeInterval(60) { return cached.token }
        if let pending { return try await pending.value }
        let task = Task { try await self.obtainToken() }
        pending = task
        defer { pending = nil }
        return try await task.value
    }

    private func obtainToken() async throws -> String {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let config = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let apiKey = config["API_KEY"] as? String else { throw IdentityError.configuration }
        let refresh = try readRefresh()
        let endpoint = refresh == nil
            ? "https://identitytoolkit.googleapis.com/v1/accounts:signUp"
            : "https://securetoken.googleapis.com/v1/token"
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        if let refresh {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let encoded = refresh.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
            request.httpBody = Data("grant_type=refresh_token&refresh_token=\(encoded)".utf8)
        } else {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        }
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let token = (json["idToken"] ?? json["id_token"]) as? String,
              let refreshToken = (json["refreshToken"] ?? json["refresh_token"]) as? String,
              let seconds = Double(String(describing: json["expiresIn"] ?? json["expires_in"] ?? "3600")) else {
            throw IdentityError.unavailable
        }
        try saveRefresh(refreshToken)
        cached = (token, Date().addingTimeInterval(seconds))
        return token
    }

    private func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "anonymous"]
    }

    private func readRefresh() throws -> String? {
        var query = query()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty else { throw IdentityError.keychain }
        return value
    }

    private func saveRefresh(_ value: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var entry = query(); attributes.forEach { entry[$0.key] = $0.value }
            guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw IdentityError.keychain }
        } else if status != errSecSuccess { throw IdentityError.keychain }
    }

    enum IdentityError: LocalizedError {
        case configuration, unavailable, keychain
        var errorDescription: String? {
            switch self {
            case .configuration: return "Не настроен профиль AI-чата."
            case .unavailable: return "Не удалось подключить профиль AI-чата. Проверьте интернет и попробуйте снова."
            case .keychain: return "Не удалось открыть защищённый профиль AI-чата. Разблокируйте iPhone и попробуйте снова."
            }
        }
    }
}
