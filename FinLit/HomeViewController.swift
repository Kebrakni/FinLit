import UIKit

final class HomeViewController: UIViewController {

    private var goals: [Goal] = []

    // MARK: - UI
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let fabButton = UIButton(type: .system)
    private let emptyLabel = UILabel()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Мои цели"
        view.backgroundColor = .systemBackground
        setupTableView()
        setupFAB()
        setupEmptyLabel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        goals = AppStorage.shared.loadGoals()
        updateEmpty()
        tableView.reloadData()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.register(GoalCell.self, forCellReuseIdentifier: GoalCell.reuseID)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupFAB() {
        fabButton.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        fabButton.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)
        fabButton.tintColor = .white
        fabButton.backgroundColor = .systemBlue
        fabButton.layer.cornerRadius = 30
        fabButton.layer.shadowColor  = UIColor.black.cgColor
        fabButton.layer.shadowOpacity = 0.25
        fabButton.layer.shadowOffset  = CGSize(width: 0, height: 4)
        fabButton.layer.shadowRadius  = 8
        fabButton.addTarget(self, action: #selector(didTapFAB), for: .touchUpInside)
        view.addSubview(fabButton)
        NSLayoutConstraint.activate([
            fabButton.widthAnchor.constraint(equalToConstant: 60),
            fabButton.heightAnchor.constraint(equalToConstant: 60),
            fabButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            fabButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func setupEmptyLabel() {
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.text = "Нет целей.\nНажми + чтобы добавить первую цель"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .systemFont(ofSize: 16)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
        ])
    }

    private func updateEmpty() {
        emptyLabel.isHidden = !goals.isEmpty
        tableView.isHidden  = goals.isEmpty
    }

    // MARK: - Actions

    @objc private func didTapFAB() {
        showAddGoalAlert()
    }

    private func showAddGoalAlert() {
        let alert = UIAlertController(title: "Новая цель", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Название (например: iPhone)"
        }
        alert.addTextField { tf in
            tf.placeholder = "Сумма цели (₸)"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Создать", style: .default) { [weak self] _ in
            guard let self else { return }
            let name   = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? ""
            let rawAmt = alert.textFields?[1].text?.replacingOccurrences(of: " ", with: "") ?? ""
            let target = Double(rawAmt) ?? 0
            guard !name.isEmpty, target > 0 else { return }

            var goals = AppStorage.shared.loadGoals()
            goals.append(Goal(title: name, targetAmount: target, savedAmount: 0, deadline: nil))
            AppStorage.shared.saveGoals(goals)
            self.goals = goals
            self.updateEmpty()
            self.tableView.reloadData()
        })
        present(alert, animated: true)
    }

    private func showAddSavingsAlert(for index: Int) {
        let goal = goals[index]
        let alert = UIAlertController(
            title: "Пополнить «\(goal.title)»",
            message: "Сколько отложил(а)?",
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.placeholder = "Сумма"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Добавить", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw   = alert.textFields?.first?.text?.replacingOccurrences(of: " ", with: "") ?? ""
            let value = Double(raw) ?? 0
            guard value > 0 else { return }
            self.goals[index].savedAmount += value
            AppStorage.shared.saveGoals(self.goals)
            self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
        })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        goals.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: GoalCell.reuseID, for: indexPath) as! GoalCell
        cell.configure(with: goals[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        showAddSavingsAlert(for: indexPath.row)
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, done in
            guard let self else { done(false); return }
            self.goals.remove(at: indexPath.row)
            AppStorage.shared.saveGoals(self.goals)
            tableView.deleteRows(at: [indexPath], with: .automatic)
            self.updateEmpty()
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - GoalCell

final class GoalCell: UITableViewCell {

    static let reuseID = "GoalCell"

    private let titleLabel   = UILabel()
    private let amountsLabel = UILabel()
    private let progressBg   = UIView()
    private let progressFill = UIView()
    private let percentLabel = UILabel()
    private let addHint      = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        selectionStyle = .none

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.numberOfLines = 2

        amountsLabel.translatesAutoresizingMaskIntoConstraints = false
        amountsLabel.font = .systemFont(ofSize: 14)
        amountsLabel.textColor = .secondaryLabel

        progressBg.translatesAutoresizingMaskIntoConstraints = false
        progressBg.backgroundColor = .systemFill
        progressBg.layer.cornerRadius = 6
        progressBg.clipsToBounds = true

        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.backgroundColor = .systemBlue
        progressFill.layer.cornerRadius = 6

        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        percentLabel.textColor = .secondaryLabel

        addHint.translatesAutoresizingMaskIntoConstraints = false
        addHint.text = "Нажми чтобы пополнить →"
        addHint.font = .systemFont(ofSize: 12)
        addHint.textColor = .systemBlue

        contentView.addSubview(titleLabel)
        contentView.addSubview(amountsLabel)
        contentView.addSubview(progressBg)
        progressBg.addSubview(progressFill)
        contentView.addSubview(percentLabel)
        contentView.addSubview(addHint)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            amountsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            amountsLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            amountsLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            progressBg.topAnchor.constraint(equalTo: amountsLabel.bottomAnchor, constant: 12),
            progressBg.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            progressBg.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            progressBg.heightAnchor.constraint(equalToConstant: 12),

            progressFill.topAnchor.constraint(equalTo: progressBg.topAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressBg.leadingAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressBg.bottomAnchor),

            percentLabel.topAnchor.constraint(equalTo: progressBg.bottomAnchor, constant: 6),
            percentLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            addHint.centerYAnchor.constraint(equalTo: percentLabel.centerYAnchor),
            addHint.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            addHint.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    // Stores width constraint so we can update it
    private var fillWidthConstraint: NSLayoutConstraint?

    func configure(with goal: Goal) {
        titleLabel.text = goal.title

        let saved  = formatMoney(goal.savedAmount)
        let target = formatMoney(goal.targetAmount)
        amountsLabel.text = "\(saved) из \(target)"

        let pct = Int(goal.progress * 100)
        percentLabel.text = "\(pct)%"

        // Color fill by progress
        if goal.progress >= 1 {
            progressFill.backgroundColor = .systemGreen
            addHint.text = "✓ Цель достигнута!"
            addHint.textColor = .systemGreen
        } else if goal.progress >= 0.75 {
            progressFill.backgroundColor = .systemBlue
            addHint.text = "Нажми чтобы пополнить →"
            addHint.textColor = .systemBlue
        } else {
            progressFill.backgroundColor = .systemBlue
            addHint.text = "Нажми чтобы пополнить →"
            addHint.textColor = .systemBlue
        }

        // Update fill width constraint
        fillWidthConstraint?.isActive = false
        fillWidthConstraint = progressFill.widthAnchor.constraint(
            equalTo: progressBg.widthAnchor,
            multiplier: CGFloat(max(0.02, min(goal.progress, 1.0)))
        )
        fillWidthConstraint?.isActive = true
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "\(f.string(from: NSNumber(value: v)) ?? "0") ₸"
    }
}
