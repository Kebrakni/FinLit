import UIKit

final class HomeViewController: UIViewController {

    private var goal: Goal = AppStorage.shared.loadGoal()

    // MARK: - UI

    private let scrollView    = UIScrollView()
    private let contentStack  = UIStackView()
    private let cardView      = UIView()
    private let titleLabel    = UILabel()
    private let amountsLabel  = UILabel()
    private let progressView  = UIProgressView(progressViewStyle: .default)
    private let progressLabel = UILabel()
    private let deadlineLabel = UILabel()
    private let addButton     = UIButton(type: .system)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Цель"
        view.backgroundColor = .systemBackground
        setupNav()
        setupUI()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        goal = AppStorage.shared.loadGoal()
        render()
    }

    // MARK: - Navigation

    private func setupNav() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            style: .plain,
            target: self,
            action: #selector(didTapEdit)
        )
    }

    // MARK: - Setup UI

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
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

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
        ])

        setupGoalCard()
    }

    private func setupGoalCard() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 20

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 2

        amountsLabel.translatesAutoresizingMaskIntoConstraints = false
        amountsLabel.font = .systemFont(ofSize: 15)
        amountsLabel.textColor = .secondaryLabel

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.layer.cornerRadius = 5
        progressView.clipsToBounds = true
        progressView.trackTintColor = .systemFill
        progressView.progressTintColor = .systemBlue

        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        progressLabel.textColor = .secondaryLabel

        deadlineLabel.translatesAutoresizingMaskIntoConstraints = false
        deadlineLabel.font = .systemFont(ofSize: 13)
        deadlineLabel.textColor = .secondaryLabel
        deadlineLabel.isHidden = true

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("Я отложил(а)", for: .normal)
        addButton.setImage(UIImage(systemName: "plus.circle.fill"), for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        addButton.backgroundColor = .systemBlue
        addButton.tintColor = .white
        addButton.layer.cornerRadius = 14
        addButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 20, bottom: 14, right: 20)
        addButton.imageEdgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 8)
        addButton.titleEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        addButton.addTarget(self, action: #selector(didTapAdd), for: .touchUpInside)

        cardView.addSubview(titleLabel)
        cardView.addSubview(amountsLabel)
        cardView.addSubview(progressView)
        cardView.addSubview(progressLabel)
        cardView.addSubview(deadlineLabel)
        cardView.addSubview(addButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            amountsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            amountsLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            amountsLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            progressView.topAnchor.constraint(equalTo: amountsLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            progressView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            progressView.heightAnchor.constraint(equalToConstant: 10),

            progressLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            progressLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            progressLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            deadlineLabel.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 4),
            deadlineLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            deadlineLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),

            addButton.topAnchor.constraint(equalTo: deadlineLabel.bottomAnchor, constant: 18),
            addButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 18),
            addButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -18),
            addButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -18),
        ])

        contentStack.addArrangedSubview(cardView)
    }

    // MARK: - Render

    private func render() {
        titleLabel.text = goal.title
        amountsLabel.text = "Отложено: \(formatMoney(goal.savedAmount)) из \(formatMoney(goal.targetAmount))"

        let pct = Int(goal.progress * 100)
        progressView.setProgress(Float(goal.progress), animated: true)
        progressLabel.text = "Прогресс: \(pct)%"

        if let deadline = goal.deadline {
            let df = DateFormatter()
            df.dateFormat = "dd MMMM yyyy"
            df.locale = Locale(identifier: "ru_RU")
            let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
            if days > 0 {
                deadlineLabel.text = "Дедлайн: \(df.string(from: deadline)) · осталось \(days) дн."
                deadlineLabel.textColor = days < 14 ? .systemOrange : .secondaryLabel
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
            self.render()
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
