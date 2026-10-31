import UIKit

enum FinLitTheme {
    static let accent = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.57, green: 0.62, blue: 1, alpha: 1)
            : UIColor(red: 0.28, green: 0.33, blue: 0.83, alpha: 1)
    }
    // The hero keeps white text legible in both appearances.
    static let heroStart = UIColor(red: 0.19, green: 0.25, blue: 0.62, alpha: 1)
    static let accentSecondary = UIColor(red: 0.34, green: 0.33, blue: 0.71, alpha: 1)
    static let buttonFill = UIColor(red: 0.28, green: 0.33, blue: 0.83, alpha: 1)
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.045, green: 0.055, blue: 0.08, alpha: 1)
            : UIColor(red: 0.955, green: 0.963, blue: 0.98, alpha: 1)
    }
    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.085, green: 0.10, blue: 0.14, alpha: 1)
            : .white
    }
    static let elevatedSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.14, blue: 0.19, alpha: 1)
            : UIColor(red: 0.975, green: 0.98, blue: 0.995, alpha: 1)
    }
    static let accentSoft = UIColor { traits in
        accent.resolvedColor(with: traits).withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.14 : 0.08)
    }

    static let outline = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(traits.accessibilityContrast == .high ? 0.30 : 0.08)
            : UIColor(red: 0.16, green: 0.23, blue: 0.37, alpha: traits.accessibilityContrast == .high ? 0.35 : 0.09)
    }

    static func font(_ size: CGFloat, weight: UIFont.Weight = .regular, style: UIFont.TextStyle = .body) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    }

    static func styleCard(_ view: UIView, radius: CGFloat = 22) {
        view.backgroundColor = surface
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1 / max(view.traitCollection.displayScale, 1)
        updateCardLayers(view)
        view.layer.shadowRadius = 16
        view.layer.shadowOffset = CGSize(width: 0, height: 6)
        view.registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (view: UIView, _: UITraitCollection) in
            updateCardLayers(view)
        }
    }

    private static func updateCardLayers(_ view: UIView) {
        view.layer.borderColor = outline.resolvedColor(with: view.traitCollection).cgColor
        view.layer.shadowColor = UIColor(red: 0.10, green: 0.16, blue: 0.30, alpha: 1).cgColor
        view.layer.shadowOpacity = view.traitCollection.userInterfaceStyle == .dark ? 0 : 0.045
    }

    static func configurePrimaryButton(
        _ button: UIButton,
        title: String,
        image: String
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: image)
        configuration.imagePadding = 9
        configuration.baseBackgroundColor = buttonFill
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var result = attributes
            result.font = font(16, weight: .semibold)
            return result
        }
        configuration.preferredSymbolConfigurationForImage = .init(pointSize: 16, weight: .semibold)
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 15,
            leading: 20,
            bottom: 15,
            trailing: 20
        )
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.layer.shadowColor = buttonFill.cgColor
        button.layer.cornerCurve = .continuous
        button.layer.shadowOpacity = 0.10
        button.layer.shadowRadius = 10
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
    }
}

final class FinLitGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureGradient()
    }

    private func configureGradient() {
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        updateColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FinLitGradientView, _: UITraitCollection) in
            view.updateColors()
        }
    }

    private func updateColors() {
        gradientLayer.colors = [
            FinLitTheme.heroStart.resolvedColor(with: traitCollection).cgColor,
            FinLitTheme.accentSecondary.resolvedColor(with: traitCollection).cgColor,
        ]
    }
}

final class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        view.tintColor = FinLitTheme.accent

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tabAppearance.backgroundColor = FinLitTheme.surface.withAlphaComponent(0.86)
        tabAppearance.shadowColor = .clear
        let tabItemAppearance = UITabBarItemAppearance()
        tabItemAppearance.normal.iconColor = .secondaryLabel
        tabItemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        tabItemAppearance.selected.iconColor = FinLitTheme.accent
        tabItemAppearance.selected.titleTextAttributes = [
            .foregroundColor: FinLitTheme.accent,
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
        ]
        tabAppearance.stackedLayoutAppearance = tabItemAppearance
        tabAppearance.inlineLayoutAppearance = tabItemAppearance
        tabAppearance.compactInlineLayoutAppearance = tabItemAppearance
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance
        tabBar.tintColor = FinLitTheme.accent

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundColor = FinLitTheme.background.withAlphaComponent(0.92)
        navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        navigationAppearance.shadowColor = .clear
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: FinLitTheme.font(32, weight: .bold, style: .largeTitle),
        ]
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
        ]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = FinLitTheme.accent

        let home = UINavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "Цель", image: UIImage(systemName: "house"), selectedImage: UIImage(systemName: "house.fill"))

        let battle = UINavigationController(rootViewController: BattleViewController())
        battle.tabBarItem = UITabBarItem(title: "Битва", image: UIImage(systemName: "trophy"), selectedImage: UIImage(systemName: "trophy.fill"))

        let analytics = UINavigationController(rootViewController: AnalyticsViewController())
        analytics.tabBarItem = UITabBarItem(title: "Аналитика", image: UIImage(systemName: "chart.pie"), selectedImage: UIImage(systemName: "chart.pie.fill"))

        let settings = UINavigationController(rootViewController: SettingsViewController())
        settings.tabBarItem = UITabBarItem(title: "Настройки", image: UIImage(systemName: "gearshape"), selectedImage: UIImage(systemName: "gearshape.fill"))

        [home, battle, analytics, settings].forEach { navigation in
            navigation.navigationBar.prefersLargeTitles = true
            navigation.topViewController?.navigationItem.largeTitleDisplayMode = .always
        }

        viewControllers = [home, battle, analytics, settings]
    }
}
