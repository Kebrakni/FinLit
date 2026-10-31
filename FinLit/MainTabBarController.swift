import UIKit

enum FinLitTheme {
    static let accent = UIColor(
        red: 0.25,
        green: 0.43,
        blue: 0.98,
        alpha: 1
    )
    static let accentSecondary = UIColor(
        red: 0.50,
        green: 0.32,
        blue: 0.96,
        alpha: 1
    )
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.025, green: 0.03, blue: 0.055, alpha: 1)
            : UIColor(red: 0.955, green: 0.965, blue: 0.99, alpha: 1)
    }
    static let surface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.10, blue: 0.15, alpha: 1)
            : .white
    }
    static let elevatedSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.14, blue: 0.20, alpha: 1)
            : UIColor(red: 0.985, green: 0.988, blue: 1, alpha: 1)
    }
    static let accentSoft = UIColor { traits in
        accent.withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.22 : 0.12)
    }

    static func styleCard(_ view: UIView, radius: CGFloat = 22) {
        view.backgroundColor = surface
        view.layer.cornerRadius = radius
        view.layer.cornerCurve = .continuous
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowRadius = 18
        view.layer.shadowOffset = CGSize(width: 0, height: 8)
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
        configuration.baseBackgroundColor = accent
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 15,
            leading: 20,
            bottom: 15,
            trailing: 20
        )
        button.configuration = configuration
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.shadowColor = accent.cgColor
        button.layer.shadowOpacity = 0.22
        button.layer.shadowRadius = 12
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        updateColors()
    }

    private func configureGradient() {
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        updateColors()
    }

    private func updateColors() {
        gradientLayer.colors = [
            FinLitTheme.accent.resolvedColor(with: traitCollection).cgColor,
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
            .font: UIFont.systemFont(ofSize: 34, weight: .bold),
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
        home.tabBarItem = UITabBarItem(title: "Цель", image: UIImage(systemName: "house"), tag: 0)

        let battle = UINavigationController(rootViewController: BattleViewController())
        battle.tabBarItem = UITabBarItem(title: "Битва", image: UIImage(systemName: "trophy"), tag: 1)

        let analytics = UINavigationController(rootViewController: AnalyticsViewController())
        analytics.tabBarItem = UITabBarItem(title: "Аналитика", image: UIImage(systemName: "chart.pie"), tag: 2)

        [home, battle, analytics].forEach { navigation in
            navigation.navigationBar.prefersLargeTitles = true
            navigation.topViewController?.navigationItem.largeTitleDisplayMode = .always
        }

        viewControllers = [home, battle, analytics]
    }
}
