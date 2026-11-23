import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Sendable {
    case russian = "ru", english = "en"
    var name: String { self == .russian ? "Русский" : "English" }
    var locale: Locale { Locale(identifier: self == .russian ? "ru_KZ" : "en_KZ") }
}

nonisolated struct LanguagePreferences {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: "tengely.language") ?? "") ?? .russian }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "tengely.language") }
    }
}

nonisolated enum L10n {
    static var language: AppLanguage { LanguagePreferences().language }
    static var locale: Locale { language.locale }
    private static let bundles: [AppLanguage: Bundle] = Dictionary(uniqueKeysWithValues: AppLanguage.allCases.compactMap { language in
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"), let bundle = Bundle(path: path) else { return nil }
        return (language, bundle)
    })

    /// Named positional tokens preserve interpolation order across languages.
    /// Substitute from the end so user text containing tokens is never expanded.
    static func text(_ key: String, _ arguments: String...) -> String {
        format(bundles[language]?.localizedString(forKey: key, value: key, table: nil) ?? key, arguments: arguments)
    }

    static func format(_ template: String, arguments: [String]) -> String {
        guard !arguments.isEmpty else { return template }
        let regex = try! NSRegularExpression(pattern: #"\{(\d+)\}"#)
        let result = NSMutableString(string: template)
        let source = template as NSString
        for match in regex.matches(in: template, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let index = Int(source.substring(with: match.range(at: 1))), arguments.indices.contains(index) else { continue }
            result.replaceCharacters(in: match.range, with: arguments[index])
        }
        return result as String
    }

    static func privacyURL(_ address: String) -> String {
        guard var url = URLComponents(string: address), url.scheme == "https" else { return address }
        url.path = language == .english ? "/privacy" : "/privacy/ru"
        return url.string ?? address
    }
}
