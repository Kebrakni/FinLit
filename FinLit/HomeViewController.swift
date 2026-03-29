import UIKit

final class HomeViewController: UIViewController {

    private var goal: Goal = AppStorage.shared.loadGoal()

    // UI
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let amountsLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let progressPercentLabel = UILabel()
    private let addButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Goals"
        view.backgroundColor = .systemBackground
        setupUI()
        render()
    }

    private func setupUI() {
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 16

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.numberOfLines = 2

        amountsLabel.translatesAutoresizingMaskIntoConstraints = false
        amountsLabel.font = .systemFont(ofSize: 16, weight: .regular)
        amountsLabel.textColor = .secondaryLabel
        amountsLabel.numberOfLines = 2

        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.layer.cornerRadius = 4
        progressView.clipsToBounds = true

        progressPercentLabel.translatesAutoresizingMaskIntoConstraints = false
        progressPercentLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        progressPercentLabel.textColor = .secondaryLabel

        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("Я отложил", for: .normal)
        addButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        addButton.backgroundColor = .systemBlue
        addButton.tintColor = .white
        addButton.layer.cornerRadius = 12
        addButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        addButton.addTarget(self, action: #selector(didTapAdd), for: .touchUpInside)

        view.addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(amountsLabel)
        cardView.addSubview(progressView)
        cardView.addSubview(progressPercentLabel)
        cardView.addSubview(addButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            amountsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            amountsLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            amountsLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            progressView.topAnchor.constraint(equalTo: amountsLabel.bottomAnchor, constant: 16),
            progressView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            progressView.heightAnchor.constraint(equalToConstant: 8),

            progressPercentLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            progressPercentLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            progressPercentLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),

            addButton.topAnchor.constraint(equalTo: progressPercentLabel.bottomAnchor, constant: 16),
            addButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            addButton.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16),
        ])
    }

    private func render() {
        titleLabel.text = goal.title

        let saved = formatMoney(goal.savedAmount)
        let target = formatMoney(goal.targetAmount)
        amountsLabel.text = "Saved: \(saved) / \(target)"

        let p = Float(goal.progress)
        progressView.setProgress(p, animated: true)
        progressPercentLabel.text = "Progress: \(Int(goal.progress * 100))%"
    }

    @objc private func didTapAdd() {
        // Простое окно ввода суммы
        let alert = UIAlertController(title: "Сколько отложил(а)?",
                                      message: "Введи сумму",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "например 5000"
            tf.keyboardType = .numberPad
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            let text = alert.textFields?.first?.text ?? ""
            let value = Double(text.replacingOccurrences(of: " ", with: "")) ?? 0
            guard value > 0 else { return }

            self.goal.savedAmount += value
            AppStorage.shared.saveGoal(self.goal)
            self.render()
        }))
        present(alert, animated: true)
    }

    private func formatMoney(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let s = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "\(s) ₸"
    }
}
