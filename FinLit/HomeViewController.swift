import UIKit

struct HomeMissionPresentation: Hashable {
    let id: String
    let title: String
    let detail: String
    let progress: Double
    let progressText: String
    let xpReward: Int
    let isCompleted: Bool
}

struct HomeAchievementPresentation: Hashable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let color: UIColor
    let xpReward: Int
    let isUnlocked: Bool
    let unlockedAt: Date?

    static func == (lhs: HomeAchievementPresentation, rhs: HomeAchievementPresentation) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.detail == rhs.detail
            && lhs.symbol == rhs.symbol
            && lhs.xpReward == rhs.xpReward
            && lhs.isUnlocked == rhs.isUnlocked
            && lhs.unlockedAt == rhs.unlockedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(detail)
        hasher.combine(symbol)
        hasher.combine(xpReward)
        hasher.combine(isUnlocked)
        hasher.combine(unlockedAt)
    }
}

struct HomeGamificationPresentation {
    let level: Int
    let levelTitle: String
    let currentXP: Int
    let nextLevelXP: Int
    let weeklyStreak: Int
    let missions: [HomeMissionPresentation]
    let achievements: [HomeAchievementPresentation]

    static let empty = HomeGamificationPresentation(
        level: 1,
        levelTitle: "Новичок",
        currentXP: 0,
        nextLevelXP: 100,
        weeklyStreak: 0,
        missions: [],
        achievements: []
    )
}

final class HomeViewController: UIViewController {

    private var goal: Goal = AppStorage.shared.loadGoal()
    private var missionGenerationTask: Task<Void, Never>?
    private var isGeneratingAIMissions = false

    // MARK: - UI

    private let scrollView    = UIScrollView()
    private let contentStack  = UIStackView()
    private let cardView      = FinLitGradientView()
    private let eyebrowLabel  = UILabel()
    private let goalIconView  = UIView()
    private let goalIcon      = UIImageView(image: UIImage(systemName: "target"))
    private let titleLabel    = UILabel()
    private let amountsLabel  = UILabel()
    private let progressView  = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()
    private let deadlineLabel = UILabel()
    private let addButton     = UIButton(type: .system)
    private let journeyView = HomeGoalJourneyView()
    private let levelCard = HomeLevelCardView()
    private let missionsHeader = HomeSectionHeaderView(
        title: "Миссии недели",
        subtitle: "Персональные задания по вашей аналитике"
    )
    private let missionsStack = UIStackView()
    private let missionsEmptyView = HomeEmptyMissionsView()
    private let achievementsHeader = HomeSectionHeaderView(
        title: "Достижения",
        subtitle: "Открывайте награды за полезные привычки"
    )
    private let achievementsScrollView = UIScrollView()
    private let achievementsStack = UIStackView()
    private var gamificationPresentation = HomeGamificationPresentation.empty

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Цель"
        view.backgroundColor = FinLitTheme.background
        setupNav()
        setupUI()
        render()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gamificationDidUpdate),
            name: GamificationManager.updatedNotification,
            object: nil
        )
        GamificationManager.shared.markActivity()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        goal = AppStorage.shared.loadGoal()
        render()
        refreshGamification()
        refreshAIMissionsIfNeeded()
    }

    deinit {
        missionGenerationTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Navigation

    private func setupNav() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "pencil"),
            style: .plain,
            target: self,
            action: #selector(didTapEdit)
        )
    }

    // MARK: - Setup UI

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 16
        scrollView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        setupGoalCard()
        setupGamificationUI()
        applyGamification(gamificationPresentation)
    }

    private func setupGoalCard() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 28
        cardView.layer.cornerCurve = .continuous
        cardView.layer.masksToBounds = false
        cardView.layer.shadowColor = FinLitTheme.accent.cgColor
        cardView.layer.shadowOpacity = 0.24
        cardView.layer.shadowRadius = 24
        cardView.layer.shadowOffset = CGSize(width: 0, height: 14)

        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.text = "ВАША ФИНАНСОВАЯ ЦЕЛЬ"
        eyebrowLabel.font = .systemFont(ofSize: 11, weight: .bold)
        eyebrowLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        eyebrowLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        goalIconView.translatesAutoresizingMaskIntoConstraints = false
        goalIconView.backgroundColor = UIColor.white.withAlphaComponent(0.16)
        goalIconView.layer.cornerRadius = 20
        goalIconView.layer.cornerCurve = .continuous

        goalIcon.translatesAutoresizingMaskIntoConstraints = false
        goalIcon.tintColor = .white
        goalIcon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 19, weight: .semibold)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 28, weight: .bold)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 2

        amountsLabel.translatesAutoresizingMaskIntoConstraints = false
        amountsLabel.font = .systemFont(ofSize: 15, weight: .medium)
        amountsLabel.textColor = UIColor.white.withAlphaComponent(0.78)
        amountsLabel.numberOfLines = 2

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.layer.cornerRadius = 5
        progressView.clipsToBounds = true
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.18)
        progressView.progressTintColor = .white

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .systemFont(ofSize: 14, weight: .bold)
        progressLabel.textColor = .white

        deadlineLabel.translatesAutoresizingMaskIntoConstraints = false
        deadlineLabel.font = .systemFont(ofSize: 13)
        deadlineLabel.textColor = UIColor.white.withAlphaComponent(0.72)
        deadlineLabel.isHidden = true

        addButton.translatesAutoresizingMaskIntoConstraints = false
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = "Добавить накопление"
        buttonConfiguration.image = UIImage(systemName: "plus")
        buttonConfiguration.imagePadding = 8
        buttonConfiguration.baseBackgroundColor = .white
        buttonConfiguration.baseForegroundColor = FinLitTheme.accent
        buttonConfiguration.cornerStyle = .large
        buttonConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
        addButton.configuration = buttonConfiguration
        addButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        addButton.addTarget(self, action: #selector(didTapAdd), for: .touchUpInside)

        cardView.addSubview(eyebrowLabel)
        cardView.addSubview(goalIconView)
        goalIconView.addSubview(goalIcon)
        cardView.addSubview(titleLabel)
        cardView.addSubview(amountsLabel)
        cardView.addSubview(progressView)
        cardView.addSubview(progressLabel)
        cardView.addSubview(deadlineLabel)
        cardView.addSubview(addButton)

        NSLayoutConstraint.activate([
            eyebrowLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 24),
            eyebrowLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            eyebrowLabel.trailingAnchor.constraint(lessThanOrEqualTo: goalIconView.leadingAnchor, constant: -12),
            eyebrowLabel.centerYAnchor.constraint(equalTo: goalIconView.centerYAnchor),

            goalIconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 18),
            goalIconView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            goalIconView.widthAnchor.constraint(equalToConstant: 40),
            goalIconView.heightAnchor.constraint(equalToConstant: 40),

            goalIcon.centerXAnchor.constraint(equalTo: goalIconView.centerXAnchor),
            goalIcon.centerYAnchor.constraint(equalTo: goalIconView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: goalIconView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),

            amountsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            amountsLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            amountsLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),

            progressView.topAnchor.constraint(equalTo: amountsLabel.bottomAnchor, constant: 22),
            progressView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            progressView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),
            progressView.heightAnchor.constraint(equalToConstant: 10),

            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            progressLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            progressLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),

            deadlineLabel.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 4),
            deadlineLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            deadlineLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),

            addButton.topAnchor.constraint(equalTo: deadlineLabel.bottomAnchor, constant: 18),
            addButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 22),
            addButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -22),
            addButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -22),
        ])

        contentStack.addArrangedSubview(cardView)
    }

    private func setupGamificationUI() {
        journeyView.translatesAutoresizingMaskIntoConstraints = false
        levelCard.translatesAutoresizingMaskIntoConstraints = false

        missionsStack.axis = .vertical
        missionsStack.spacing = 10
        missionsStack.alignment = .fill
        missionsStack.translatesAutoresizingMaskIntoConstraints = false

        achievementsScrollView.translatesAutoresizingMaskIntoConstraints = false
        achievementsScrollView.showsHorizontalScrollIndicator = false
        achievementsScrollView.alwaysBounceHorizontal = true
        achievementsScrollView.clipsToBounds = false

        achievementsStack.translatesAutoresizingMaskIntoConstraints = false
        achievementsStack.axis = .horizontal
        achievementsStack.spacing = 12
        achievementsStack.alignment = .top
        achievementsScrollView.addSubview(achievementsStack)
        NSLayoutConstraint.activate([
            achievementsStack.topAnchor.constraint(equalTo: achievementsScrollView.contentLayoutGuide.topAnchor),
            achievementsStack.bottomAnchor.constraint(equalTo: achievementsScrollView.contentLayoutGuide.bottomAnchor),
            achievementsStack.leadingAnchor.constraint(equalTo: achievementsScrollView.contentLayoutGuide.leadingAnchor),
            achievementsStack.trailingAnchor.constraint(equalTo: achievementsScrollView.contentLayoutGuide.trailingAnchor),
            achievementsStack.heightAnchor.constraint(equalTo: achievementsScrollView.frameLayoutGuide.heightAnchor),
            achievementsScrollView.heightAnchor.constraint(equalToConstant: 104),
        ])

        contentStack.addArrangedSubview(journeyView)
        contentStack.addArrangedSubview(levelCard)
        contentStack.setCustomSpacing(24, after: levelCard)
        contentStack.addArrangedSubview(missionsHeader)
        contentStack.setCustomSpacing(10, after: missionsHeader)
        contentStack.addArrangedSubview(missionsStack)
        contentStack.setCustomSpacing(24, after: missionsStack)
        contentStack.addArrangedSubview(achievementsHeader)
        contentStack.setCustomSpacing(12, after: achievementsHeader)
        contentStack.addArrangedSubview(achievementsScrollView)
    }

    // MARK: - Render

    private func render() {
        titleLabel.text = goal.title
        let statementSavings = max(AppStorage.shared.loadPDFNetSavings(), 0)
        let manualSavings = max(goal.savedAmount, 0)
        let combinedSavings = statementSavings + manualSavings
        var displayedGoal = goal
        displayedGoal.savedAmount = combinedSavings
        amountsLabel.text = "\(formatMoney(combinedSavings)) из \(formatMoney(goal.targetAmount))\nВыписка: \(formatMoney(statementSavings)) · Вручную: \(formatMoney(manualSavings))"

        let pct = Int(displayedGoal.progress * 100)
        progressView.setProgress(Float(displayedGoal.progress), animated: true)
        progressLabel.text = "\(pct)% выполнено"
        journeyView.configure(savedAmount: combinedSavings, targetAmount: goal.targetAmount)

        if let deadline = goal.deadline {
            let df = DateFormatter()
            df.dateFormat = "dd MMMM yyyy"
            df.locale = Locale(identifier: "ru_RU")
            let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
            if days > 0 {
                deadlineLabel.text = "До \(df.string(from: deadline)) · осталось \(days) дн."
                deadlineLabel.textColor = days < 14 ? .systemYellow : UIColor.white.withAlphaComponent(0.72)
            } else if days == 0 {
                deadlineLabel.text = "Дедлайн: сегодня!"
                deadlineLabel.textColor = .systemRed
            } else {
                deadlineLabel.text = "Дедлайн прошёл \(df.string(from: deadline))"
                deadlineLabel.textColor = .systemRed
            }
            deadlineLabel.isHidden = false
        } else {
            deadlineLabel.isHidden = true
        }
    }

    func applyGamification(_ presentation: HomeGamificationPresentation) {
        gamificationPresentation = presentation
        guard isViewLoaded else { return }

        levelCard.configure(
            level: presentation.level,
            title: presentation.levelTitle,
            currentXP: presentation.currentXP,
            nextLevelXP: presentation.nextLevelXP,
            streak: presentation.weeklyStreak
        )

        missionsStack.arrangedSubviews.forEach { view in
            missionsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if presentation.missions.isEmpty {
            missionsStack.addArrangedSubview(missionsEmptyView)
        } else {
            presentation.missions.prefix(3).forEach { mission in
                let card = HomeMissionCardView()
                card.configure(with: mission)
                missionsStack.addArrangedSubview(card)
            }
        }

        achievementsStack.arrangedSubviews.forEach { view in
            achievementsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let achievements = presentation.achievements.isEmpty
            ? HomeAchievementPresentation.defaults
            : presentation.achievements
        achievements.forEach { achievement in
            let badge = HomeAchievementBadgeView()
            badge.configure(with: achievement)
            badge.onTap = { [weak self] in
                self?.showAchievementDetails(achievement)
            }
            achievementsStack.addArrangedSubview(badge)
        }
    }

    @objc private func gamificationDidUpdate() {
        refreshGamification()
    }

    private func refreshGamification() {
        let snapshot = GamificationManager.shared.snapshot(
            transactions: AppStorage.shared.loadAllTransactions(),
            goal: AppStorage.shared.loadGoalIncludingStatementSavings()
        )
        let earnedInLevel = max(snapshot.xp - snapshot.currentLevelXP, 0)
        let requiredInLevel = max(
            (snapshot.nextLevelXP ?? snapshot.xp) - snapshot.currentLevelXP,
            1
        )
        let missions = snapshot.missions.map { mission in
            HomeMissionPresentation(
                id: mission.id,
                title: mission.title,
                detail: mission.detail,
                progress: mission.progress,
                progressText: missionProgressText(mission),
                xpReward: mission.xpReward,
                isCompleted: mission.isCompleted
            )
        }
        let achievements = snapshot.achievements.map { achievement in
            HomeAchievementPresentation(
                id: achievement.id,
                title: achievement.title,
                detail: achievement.detail,
                symbol: achievement.icon,
                color: achievementColor(for: achievement.id),
                xpReward: achievement.xpReward,
                isUnlocked: achievement.isUnlocked,
                unlockedAt: achievement.unlockedAt
            )
        }
        applyGamification(
            HomeGamificationPresentation(
                level: snapshot.level,
                levelTitle: snapshot.levelTitle,
                currentXP: earnedInLevel,
                nextLevelXP: requiredInLevel,
                weeklyStreak: snapshot.streak,
                missions: missions,
                achievements: achievements
            )
        )
    }

    private func refreshAIMissionsIfNeeded() {
        let manager = GamificationManager.shared
        let transactions = AppStorage.shared.loadAllTransactions()
        guard manager.needsAIMissions(),
              !transactions.isEmpty,
              !isGeneratingAIMissions else { return }

        isGeneratingAIMissions = true
        let currentGoal = AppStorage.shared.loadGoalIncludingStatementSavings()
        missionGenerationTask = Task { [weak self] in
            do {
                let suggestions = try await OpenRouterCategorizer.shared.generateWeeklyMissions(
                    transactions: transactions,
                    goal: currentGoal
                )
                guard !Task.isCancelled else { return }
                let missions = Self.weeklyMissions(from: suggestions)
                guard missions.count == 3 else {
                    await MainActor.run { self?.isGeneratingAIMissions = false }
                    return
                }
                await MainActor.run {
                    GamificationManager.shared.installWeeklyMissions(missions)
                    self?.isGeneratingAIMissions = false
                    self?.refreshGamification()
                }
            } catch {
                // The locally generated missions remain available when the free
                // model is busy or the device is offline.
                await MainActor.run {
                    self?.isGeneratingAIMissions = false
                }
            }
        }
    }

    private static func weeklyMissions(
        from suggestions: [OpenRouterCategorizer.MissionSuggestion]
    ) -> [WeeklyMission] {
        let weekID = GamificationManager.weekID()
        var usedKinds = Set<MissionKind>()
        return suggestions.compactMap { suggestion in
            let kind: MissionKind
            switch suggestion.kind {
            case "save_amount": kind = .saveAmount
            case "review_operations": kind = .reviewOperations
            case "category_budget": kind = .categoryBudget
            case "no_spend_days": kind = .noSpendDays
            default: return nil
            }
            guard !usedKinds.contains(kind), suggestion.target > 0 else { return nil }
            let categoryCode: String?
            if kind == .categoryBudget,
               TxCategory(aiCode: suggestion.category) != nil {
                categoryCode = suggestion.category
            } else if kind == .categoryBudget {
                return nil
            } else {
                categoryCode = nil
            }
            usedKinds.insert(kind)
            let target: Double
            switch kind {
            case .reviewOperations:
                target = min(max(suggestion.target.rounded(), 3), 12)
            case .noSpendDays:
                target = min(max(suggestion.target.rounded(), 1), 3)
            case .saveAmount, .categoryBudget:
                target = max(suggestion.target.rounded(), 100)
            }
            let reward: Int
            switch kind {
            case .saveAmount: reward = 60
            case .reviewOperations: reward = 45
            case .categoryBudget, .noSpendDays: reward = 55
            }
            return WeeklyMission(
                id: "\(weekID):ai:\(kind.rawValue)",
                weekID: weekID,
                title: suggestion.title,
                detail: suggestion.detail,
                kind: kind,
                target: target,
                categoryCode: categoryCode,
                xpReward: reward,
                generatedByAI: true
            )
        }
    }

    private func missionProgressText(_ mission: WeeklyMission) -> String {
        switch mission.kind {
        case .saveAmount:
            return "\(formatMoney(mission.current)) из \(formatMoney(mission.target))"
        case .reviewOperations:
            return "\(Int(mission.current)) из \(Int(mission.target)) операций"
        case .categoryBudget:
            return mission.isCompleted
                ? "Лимит соблюдён"
                : "\(Int(mission.progress * 100))% недели по плану"
        case .noSpendDays:
            return "\(Int(mission.current)) из \(Int(mission.target)) дней"
        }
    }

    private func achievementColor(for id: String) -> UIColor {
        switch id {
        case "first_statement", "hundred_operations": return FinLitTheme.accent
        case "positive_balance", "goal_25": return .systemGreen
        case "goal_50", "saved_100k": return .systemOrange
        case "goal_100": return .systemYellow
        case "streak_4": return .systemPink
        case "corrections_10": return .systemPurple
        default: return FinLitTheme.accent
        }
    }

    private func showAchievementDetails(_ achievement: HomeAchievementPresentation) {
        let details = HomeAchievementDetailViewController(achievement: achievement)
        details.modalPresentationStyle = .pageSheet
        if let sheet = details.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 28
        }
        present(details, animated: true)
    }

    // MARK: - Actions

    @objc private func didTapAdd() {
        let alert = UIAlertController(title: "Сколько отложил(а)?",
                                      message: "Введи сумму в тенге",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "например 5000"
            tf.keyboardType = .decimalPad
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self] _ in
            guard let self else { return }
            let text = alert.textFields?.first?.text ?? ""
            let value = Double(text
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")) ?? 0
            guard value > 0 else { return }
            self.goal.savedAmount += value
            AppStorage.shared.saveGoal(self.goal)
            GamificationManager.shared.recordGoalContribution(amount: value)
            self.render()
            self.refreshGamification()
        })
        present(alert, animated: true)
    }

    @objc private func didTapEdit() {
        let alert = UIAlertController(title: "Редактировать цель", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.placeholder = "Название цели"
            tf.text = self?.goal.title
        }
        alert.addTextField { [weak self] tf in
            tf.placeholder = "Целевая сумма ₸"
            tf.keyboardType = .decimalPad
            if let g = self?.goal { tf.text = "\(Int(g.targetAmount))" }
        }
        alert.addTextField { [weak self] tf in
            tf.placeholder = "Дедлайн дд.мм.гггг (необязательно)"
            if let d = self?.goal.deadline {
                let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
                tf.text = df.string(from: d)
            }
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Сохранить", style: .default) { [weak self] _ in
            guard let self, let fields = alert.textFields else { return }
            let newTitle = fields[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !newTitle.isEmpty { self.goal.title = newTitle }
            if let raw = fields[1].text,
               let amount = Double(raw.replacingOccurrences(of: " ", with: "")
                                      .replacingOccurrences(of: ",", with: ".")),
               amount > 0 {
                self.goal.targetAmount = amount
            }
            let rawDate = fields[2].text ?? ""
            if rawDate.isEmpty {
                self.goal.deadline = nil
            } else {
                let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy"
                self.goal.deadline = df.date(from: rawDate)
            }
            AppStorage.shared.saveGoal(self.goal)
            self.render()
            self.refreshGamification()
        })
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: value)) ?? "\(Int(value))") ₸"
    }
}

private extension HomeAchievementPresentation {
    static let defaults: [HomeAchievementPresentation] = [
        .init(id: "first_statement", title: "Первая выписка", detail: "Загрузить первую банковскую выписку", symbol: "doc.text.fill", color: FinLitTheme.accent, xpReward: 25, isUnlocked: false, unlockedAt: nil),
        .init(id: "goal_25", title: "Первый рубеж", detail: "Накопить 25% финансовой цели", symbol: "flag.fill", color: .systemOrange, xpReward: 35, isUnlocked: false, unlockedAt: nil),
        .init(id: "positive_balance", title: "В плюсе", detail: "Получить положительный баланс по выпискам", symbol: "chart.line.uptrend.xyaxis", color: .systemGreen, xpReward: 40, isUnlocked: false, unlockedAt: nil),
        .init(id: "streak_4", title: "Месяц дисциплины", detail: "Поддерживать активность четыре недели подряд", symbol: "flame.fill", color: .systemPink, xpReward: 80, isUnlocked: false, unlockedAt: nil),
    ]
}

final class HomeSectionHeaderView: UIView {
    init(title: String, subtitle: String) {
        super.init(frame: .zero)
        let titleLabel = UILabel()
        let subtitleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = .label
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class HomeGoalJourneyView: UIView {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let routeStack = UIStackView()
    private let milestoneStack = UIStackView()
    private var nodes: [(container: UIView, icon: UIImageView)] = []
    private var connectors: [UIView] = []
    private var milestoneLabels: [UILabel] = []
    private let thresholds: [Double] = [0.25, 0.50, 0.75, 1]
    private let milestoneNames = ["Первый рубеж", "Половина", "Почти у цели", "Цель"]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        FinLitTheme.styleCard(self, radius: 22)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = "Путь к цели"
        titleLabel.font = .systemFont(ofSize: 17, weight: .bold)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subtitleLabel.textColor = .secondaryLabel

        routeStack.translatesAutoresizingMaskIntoConstraints = false
        routeStack.axis = .horizontal
        routeStack.alignment = .center
        routeStack.distribution = .fill

        for index in thresholds.indices {
            let node = UIView()
            let icon = UIImageView(image: UIImage(systemName: "circle"))
            node.translatesAutoresizingMaskIntoConstraints = false
            icon.translatesAutoresizingMaskIntoConstraints = false
            node.layer.cornerRadius = 17
            node.layer.cornerCurve = .continuous
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            node.addSubview(icon)
            NSLayoutConstraint.activate([
                node.widthAnchor.constraint(equalToConstant: 34),
                node.heightAnchor.constraint(equalToConstant: 34),
                icon.centerXAnchor.constraint(equalTo: node.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: node.centerYAnchor),
            ])
            routeStack.addArrangedSubview(node)
            nodes.append((node, icon))

            if index < thresholds.count - 1 {
                let connector = UIView()
                connector.translatesAutoresizingMaskIntoConstraints = false
                connector.layer.cornerRadius = 1.5
                connector.widthAnchor.constraint(greaterThanOrEqualToConstant: 16).isActive = true
                connector.heightAnchor.constraint(equalToConstant: 3).isActive = true
                routeStack.addArrangedSubview(connector)
                connectors.append(connector)
            }
        }

        milestoneStack.translatesAutoresizingMaskIntoConstraints = false
        milestoneStack.axis = .horizontal
        milestoneStack.alignment = .top
        milestoneStack.distribution = .fillEqually
        for _ in thresholds.indices {
            let label = UILabel()
            label.textAlignment = .center
            label.numberOfLines = 3
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            label.textColor = .secondaryLabel
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.72
            milestoneStack.addArrangedSubview(label)
            milestoneLabels.append(label)
        }

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(routeStack)
        addSubview(milestoneStack)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            routeStack.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            routeStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            routeStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            milestoneStack.topAnchor.constraint(equalTo: routeStack.bottomAnchor, constant: 9),
            milestoneStack.leadingAnchor.constraint(equalTo: routeStack.leadingAnchor, constant: -10),
            milestoneStack.trailingAnchor.constraint(equalTo: routeStack.trailingAnchor, constant: 10),
            milestoneStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -17),
        ])
        configure(savedAmount: 0, targetAmount: 1)
    }

    func configure(savedAmount: Double, targetAmount: Double) {
        let safeTarget = max(targetAmount, 1)
        let safeSaved = max(savedAmount, 0)
        let value = min(safeSaved / safeTarget, 1)
        if let nextIndex = thresholds.firstIndex(where: { $0 > value }) {
            let nextAmount = safeTarget * thresholds[nextIndex]
            let remaining = max(nextAmount - safeSaved, 0)
            subtitleLabel.text = "До этапа «\(milestoneNames[nextIndex])» осталось \(Self.moneyText(remaining))"
        } else {
            subtitleLabel.text = "Цель достигнута — путь завершён"
        }

        for index in nodes.indices {
            let isReached = value >= thresholds[index]
            let isNext = !isReached && (index == 0 || value >= thresholds[index - 1])
            nodes[index].container.backgroundColor = isReached
                ? FinLitTheme.accent
                : (isNext ? FinLitTheme.accentSoft : UIColor.systemFill)
            let symbol: String
            if isReached {
                symbol = "checkmark"
            } else if isNext {
                symbol = "arrow.right"
            } else if index == thresholds.count - 1 {
                symbol = "flag.checkered"
            } else {
                symbol = "circle"
            }
            nodes[index].icon.image = UIImage(systemName: symbol)
            nodes[index].icon.tintColor = isReached
                ? .white
                : (isNext ? FinLitTheme.accent : .tertiaryLabel)
            milestoneLabels[index].text = "\(Int(thresholds[index] * 100))%\n\(milestoneNames[index])\n\(Self.moneyText(safeTarget * thresholds[index]))"
            milestoneLabels[index].textColor = isReached
                ? FinLitTheme.accent
                : (isNext ? .label : .secondaryLabel)
        }
        for index in connectors.indices {
            connectors[index].backgroundColor = value >= thresholds[index + 1]
                ? FinLitTheme.accent
                : UIColor.systemFill
        }
    }

    private static func moneyText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: value)) ?? String(Int(value))
        return "\(number) ₸"
    }
}

final class HomeLevelCardView: UIView {
    private let iconBackground = UIView()
    private let iconView = UIImageView(image: UIImage(systemName: "shield.lefthalf.filled"))
    private let levelLabel = UILabel()
    private let titleLabel = UILabel()
    private let streakLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let xpLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        FinLitTheme.styleCard(self, radius: 22)

        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.backgroundColor = FinLitTheme.accentSoft
        iconBackground.layer.cornerRadius = 24
        iconBackground.layer.cornerCurve = .continuous
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = FinLitTheme.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)

        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        levelLabel.font = .systemFont(ofSize: 11, weight: .bold)
        levelLabel.textColor = FinLitTheme.accent
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)

        streakLabel.translatesAutoresizingMaskIntoConstraints = false
        streakLabel.font = .systemFont(ofSize: 12, weight: .bold)
        streakLabel.textAlignment = .center
        streakLabel.textColor = .systemOrange
        streakLabel.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.12)
        streakLabel.layer.cornerRadius = 13
        streakLabel.layer.cornerCurve = .continuous
        streakLabel.clipsToBounds = true

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .systemFill
        progressView.progressTintColor = FinLitTheme.accent
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true
        xpLabel.translatesAutoresizingMaskIntoConstraints = false
        xpLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        xpLabel.textColor = .secondaryLabel
        xpLabel.textAlignment = .right

        addSubview(iconBackground)
        iconBackground.addSubview(iconView)
        addSubview(levelLabel)
        addSubview(titleLabel)
        addSubview(streakLabel)
        addSubview(progressView)
        addSubview(xpLabel)
        NSLayoutConstraint.activate([
            iconBackground.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconBackground.widthAnchor.constraint(equalToConstant: 48),
            iconBackground.heightAnchor.constraint(equalToConstant: 48),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            levelLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 12),
            levelLabel.topAnchor.constraint(equalTo: iconBackground.topAnchor, constant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: levelLabel.leadingAnchor),
            titleLabel.topAnchor.constraint(equalTo: levelLabel.bottomAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: streakLabel.leadingAnchor, constant: -8),
            streakLabel.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            streakLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            streakLabel.heightAnchor.constraint(equalToConstant: 26),
            streakLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            progressView.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 18),
            progressView.leadingAnchor.constraint(equalTo: iconBackground.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            progressView.heightAnchor.constraint(equalToConstant: 8),
            xpLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 7),
            xpLabel.leadingAnchor.constraint(equalTo: progressView.leadingAnchor),
            xpLabel.trailingAnchor.constraint(equalTo: progressView.trailingAnchor),
            xpLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ])
    }

    func configure(level: Int, title: String, currentXP: Int, nextLevelXP: Int, streak: Int) {
        levelLabel.text = "УРОВЕНЬ \(max(level, 1))"
        titleLabel.text = title
        streakLabel.text = "  🔥 \(max(streak, 0)) нед.  "
        let target = max(nextLevelXP, 1)
        progressView.setProgress(Float(min(max(Double(currentXP) / Double(target), 0), 1)), animated: true)
        xpLabel.text = "\(max(currentXP, 0)) / \(target) XP"
    }
}

final class HomeMissionCardView: UIView {
    private let iconBackground = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()
    private let rewardLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        backgroundColor = FinLitTheme.surface
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.withAlphaComponent(0.14).cgColor

        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.layer.cornerRadius = 18
        iconBackground.layer.cornerCurve = .continuous
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .bold)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.numberOfLines = 2
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = .systemFont(ofSize: 12, weight: .medium)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 2

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .systemFill
        progressView.layer.cornerRadius = 3
        progressView.clipsToBounds = true
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        progressLabel.textColor = .secondaryLabel
        rewardLabel.translatesAutoresizingMaskIntoConstraints = false
        rewardLabel.font = .systemFont(ofSize: 11, weight: .bold)
        rewardLabel.textAlignment = .center
        rewardLabel.layer.cornerRadius = 11
        rewardLabel.layer.cornerCurve = .continuous
        rewardLabel.clipsToBounds = true

        addSubview(iconBackground)
        iconBackground.addSubview(iconView)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(progressView)
        addSubview(progressLabel)
        addSubview(rewardLabel)
        NSLayoutConstraint.activate([
            iconBackground.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBackground.widthAnchor.constraint(equalToConstant: 36),
            iconBackground.heightAnchor.constraint(equalToConstant: 36),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            rewardLabel.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            rewardLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            rewardLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
            rewardLabel.heightAnchor.constraint(equalToConstant: 23),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 15),
            titleLabel.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 11),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: rewardLabel.leadingAnchor, constant: -8),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            progressView.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 13),
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            progressView.heightAnchor.constraint(equalToConstant: 6),
            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 7),
            progressLabel.leadingAnchor.constraint(equalTo: progressView.leadingAnchor),
            progressLabel.trailingAnchor.constraint(equalTo: progressView.trailingAnchor),
            progressLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
        ])
    }

    func configure(with mission: HomeMissionPresentation) {
        let color: UIColor = mission.isCompleted ? .systemGreen : FinLitTheme.accent
        iconBackground.backgroundColor = color.withAlphaComponent(0.13)
        iconView.image = UIImage(systemName: mission.isCompleted ? "checkmark" : "flag.fill")
        iconView.tintColor = color
        titleLabel.text = mission.title
        detailLabel.text = mission.detail
        progressView.progressTintColor = color
        progressView.setProgress(Float(min(max(mission.progress, 0), 1)), animated: true)
        progressLabel.text = mission.isCompleted ? "Выполнено" : mission.progressText
        progressLabel.textColor = mission.isCompleted ? .systemGreen : .secondaryLabel
        rewardLabel.text = " +\(mission.xpReward) XP "
        rewardLabel.textColor = color
        rewardLabel.backgroundColor = color.withAlphaComponent(0.12)
    }
}

final class HomeEmptyMissionsView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = FinLitTheme.surface
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: "sparkles"))
        let label = UILabel()
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = FinLitTheme.accent
        label.text = "Загрузите выписку — AI подготовит задания на эту неделю"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 17),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 17),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -17),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -17),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

final class HomeAchievementBadgeView: UIView {
    var onTap: (() -> Void)?

    private let circle = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let lockView = UIImageView(image: UIImage(systemName: "lock.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 82).isActive = true
        isUserInteractionEnabled = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTap)))

        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.layer.cornerRadius = 25
        circle.layer.cornerCurve = .continuous
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        lockView.translatesAutoresizingMaskIntoConstraints = false
        lockView.tintColor = .secondaryLabel
        lockView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        lockView.backgroundColor = FinLitTheme.surface
        lockView.layer.cornerRadius = 8
        lockView.layer.cornerCurve = .continuous

        addSubview(circle)
        circle.addSubview(icon)
        addSubview(lockView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            circle.topAnchor.constraint(equalTo: topAnchor),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.widthAnchor.constraint(equalToConstant: 50),
            circle.heightAnchor.constraint(equalToConstant: 50),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            lockView.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: 2),
            lockView.bottomAnchor.constraint(equalTo: circle.bottomAnchor, constant: 2),
            lockView.widthAnchor.constraint(equalToConstant: 16),
            lockView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func didTap() {
        UIView.animate(withDuration: 0.08, animations: {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }) { _ in
            UIView.animate(withDuration: 0.12) { self.transform = .identity }
        }
        onTap?()
    }

    func configure(with achievement: HomeAchievementPresentation) {
        circle.backgroundColor = achievement.isUnlocked
            ? achievement.color.withAlphaComponent(0.16)
            : UIColor.systemFill
        icon.image = UIImage(systemName: achievement.symbol)
        icon.tintColor = achievement.isUnlocked ? achievement.color : .tertiaryLabel
        titleLabel.text = achievement.title
        titleLabel.textColor = achievement.isUnlocked ? .label : .tertiaryLabel
        lockView.isHidden = achievement.isUnlocked
        alpha = achievement.isUnlocked ? 1 : 0.72
        accessibilityLabel = achievement.title
        accessibilityValue = achievement.isUnlocked ? "Получено" : "Не получено"
    }
}

final class HomeAchievementDetailViewController: UIViewController {
    private let achievement: HomeAchievementPresentation

    init(achievement: HomeAchievementPresentation) {
        self.achievement = achievement
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background

        let closeButton = UIButton(type: .system)
        let iconBackground = UIView()
        let iconView = UIImageView(image: UIImage(systemName: achievement.symbol))
        let titleLabel = UILabel()
        let stateLabel = UILabel()
        let descriptionCard = UIView()
        let descriptionTitle = UILabel()
        let descriptionLabel = UILabel()
        let rewardLabel = UILabel()
        let dateLabel = UILabel()

        [closeButton, iconBackground, iconView, titleLabel, stateLabel, descriptionCard,
         descriptionTitle, descriptionLabel, rewardLabel, dateLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        var closeConfiguration = UIButton.Configuration.gray()
        closeConfiguration.image = UIImage(systemName: "xmark")
        closeConfiguration.cornerStyle = .capsule
        closeButton.configuration = closeConfiguration
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)

        iconBackground.backgroundColor = achievement.isUnlocked
            ? achievement.color.withAlphaComponent(0.16)
            : UIColor.systemFill
        iconBackground.layer.cornerRadius = 36
        iconBackground.layer.cornerCurve = .continuous
        iconView.tintColor = achievement.isUnlocked ? achievement.color : .tertiaryLabel
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .bold)

        titleLabel.text = achievement.title
        titleLabel.font = .systemFont(ofSize: 26, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2

        stateLabel.text = achievement.isUnlocked ? "  ПОЛУЧЕНО  " : "  ЕЩЁ НЕ ПОЛУЧЕНО  "
        stateLabel.font = .systemFont(ofSize: 11, weight: .bold)
        stateLabel.textAlignment = .center
        stateLabel.textColor = achievement.isUnlocked ? .systemGreen : .secondaryLabel
        stateLabel.backgroundColor = achievement.isUnlocked
            ? UIColor.systemGreen.withAlphaComponent(0.13)
            : UIColor.systemFill
        stateLabel.layer.cornerRadius = 12
        stateLabel.layer.cornerCurve = .continuous
        stateLabel.clipsToBounds = true

        FinLitTheme.styleCard(descriptionCard, radius: 20)
        descriptionTitle.text = "Как получить"
        descriptionTitle.font = .systemFont(ofSize: 13, weight: .bold)
        descriptionTitle.textColor = .secondaryLabel
        descriptionLabel.text = achievement.detail
        descriptionLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        descriptionLabel.numberOfLines = 0
        rewardLabel.text = "+\(achievement.xpReward) XP за достижение"
        rewardLabel.font = .systemFont(ofSize: 14, weight: .bold)
        rewardLabel.textColor = achievement.color

        if let unlockedAt = achievement.unlockedAt {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateStyle = .long
            formatter.timeStyle = .none
            dateLabel.text = "Получено: \(formatter.string(from: unlockedAt))"
        } else {
            dateLabel.text = "Выполни условие — дата появится здесь"
        }
        dateLabel.font = .systemFont(ofSize: 14, weight: .medium)
        dateLabel.textColor = .secondaryLabel
        dateLabel.textAlignment = .center

        view.addSubview(closeButton)
        view.addSubview(iconBackground)
        iconBackground.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(stateLabel)
        view.addSubview(descriptionCard)
        descriptionCard.addSubview(descriptionTitle)
        descriptionCard.addSubview(descriptionLabel)
        descriptionCard.addSubview(rewardLabel)
        view.addSubview(dateLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            closeButton.widthAnchor.constraint(equalToConstant: 40),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            iconBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            iconBackground.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 72),
            iconBackground.heightAnchor.constraint(equalToConstant: 72),
            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconBackground.bottomAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            stateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 9),
            stateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stateLabel.heightAnchor.constraint(equalToConstant: 25),
            descriptionCard.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 20),
            descriptionCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            descriptionCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            descriptionTitle.topAnchor.constraint(equalTo: descriptionCard.topAnchor, constant: 17),
            descriptionTitle.leadingAnchor.constraint(equalTo: descriptionCard.leadingAnchor, constant: 18),
            descriptionTitle.trailingAnchor.constraint(equalTo: descriptionCard.trailingAnchor, constant: -18),
            descriptionLabel.topAnchor.constraint(equalTo: descriptionTitle.bottomAnchor, constant: 7),
            descriptionLabel.leadingAnchor.constraint(equalTo: descriptionTitle.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: descriptionTitle.trailingAnchor),
            rewardLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 14),
            rewardLabel.leadingAnchor.constraint(equalTo: descriptionTitle.leadingAnchor),
            rewardLabel.trailingAnchor.constraint(equalTo: descriptionTitle.trailingAnchor),
            rewardLabel.bottomAnchor.constraint(equalTo: descriptionCard.bottomAnchor, constant: -17),
            dateLabel.topAnchor.constraint(equalTo: descriptionCard.bottomAnchor, constant: 16),
            dateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            dateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
