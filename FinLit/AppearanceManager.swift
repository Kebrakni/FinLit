import UIKit

@MainActor
final class AppearanceManager {
    static let shared = AppearanceManager()
    private let preferences = AppearancePreferences()

    var choice: AppearanceChoice { preferences.choice }

    func select(_ choice: AppearanceChoice) {
        preferences.choice = choice
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.windows.forEach(apply)
        }
    }

    func apply(to window: UIWindow) {
        switch preferences.choice {
        case .system: window.overrideUserInterfaceStyle = .unspecified
        case .light: window.overrideUserInterfaceStyle = .light
        case .dark: window.overrideUserInterfaceStyle = .dark
        }
    }
}
