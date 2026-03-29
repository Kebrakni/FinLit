import UIKit

final class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = UINavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)

        let challenge = UINavigationController(rootViewController: ChallengeViewController())
        challenge.tabBarItem = UITabBarItem(title: "Challenge", image: UIImage(systemName: "flag.checkered"), tag: 1)

        let battle = UINavigationController(rootViewController: BattleViewController())
        battle.tabBarItem = UITabBarItem(title: "Битва", image: UIImage(systemName: "trophy"), tag: 2)

        let analytics = UINavigationController(rootViewController: AnalyticsViewController())
        analytics.tabBarItem = UITabBarItem(title: "Analytics", image: UIImage(systemName: "chart.pie"), tag: 3)

        viewControllers = [home, challenge, battle, analytics]
    }
}
