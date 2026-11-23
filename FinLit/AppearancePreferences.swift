import Foundation

nonisolated enum AppearanceChoice: String, CaseIterable, Sendable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: return L10n.text("Как на iPhone")
        case .light: return L10n.text("Светлая")
        case .dark: return L10n.text("Тёмная")
        }
    }

    var detail: String {
        switch self {
        case .system: return L10n.text("Следует настройкам устройства")
        case .light: return L10n.text("Светлый фон и мягкие контрасты")
        case .dark: return L10n.text("Тёмные поверхности и спокойные акценты")
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }
}

nonisolated struct AppearancePreferences {
    private let defaults: UserDefaults
    private let key = "tengely.appearance"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var choice: AppearanceChoice {
        get { AppearanceChoice(rawValue: defaults.string(forKey: key) ?? "") ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key) }
    }
}
