import Foundation

nonisolated struct AIPrivacyPreferences {
    static let version = "2026-11-17-v1"
    enum Choice: String { case notAsked, allowed, declined }
    private let defaults: UserDefaults
    private let key = "tengely.ai.consent.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var choice: Choice {
        guard let record = defaults.dictionary(forKey: key), record["version"] as? String == Self.version,
              let raw = record["choice"] as? String, let choice = Choice(rawValue: raw) else { return .notAsked }
        return choice
    }

    var isAllowed: Bool { choice == .allowed }

    func set(_ choice: Choice) {
        defaults.set(["version": Self.version, "choice": choice.rawValue, "date": Date()], forKey: key)
    }
}
