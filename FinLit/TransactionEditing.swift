import UIKit

extension Transaction {
    func edited(
        merchant: String? = nil,
        details: String? = nil,
        amount: Double? = nil,
        category: TxCategory? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            date: date,
            amount: amount ?? self.amount,
            merchant: merchant ?? self.merchant,
            details: details ?? self.details,
            category: category ?? self.category
        )
    }
}

// MARK: - Transaction editor

final class TransactionEditorViewController: UIViewController {
    private let original: Transaction
    private let onSave: (Transaction) -> Void
    private var selectedCategory: TxCategory

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let merchantField = UITextField()
    private let amountField = UITextField()
    private let detailsView = UITextView()
    private let categoryButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let errorLabel = UILabel()

    init(transaction: Transaction, onSave: @escaping (Transaction) -> Void) {
        original = transaction
        selectedCategory = transaction.category
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Операция"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = FinLitTheme.background
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Отмена",
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        setupUI()
        populate()
    }

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.keyboardDismissMode = .interactive
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        let footer = UIStackView(arrangedSubviews: [errorLabel, saveButton])
        footer.axis = .vertical
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        FinLitTheme.configurePrimaryButton(saveButton, title: "Сохранить изменения", image: "checkmark")
        saveButton.addTarget(self, action: #selector(save), for: .touchUpInside)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -12),
            saveButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
        ])

        let summary = makeSummaryCard()
        stackView.addArrangedSubview(summary)
        stackView.addArrangedSubview(makeFieldCard(title: "Название", content: merchantField))
        stackView.addArrangedSubview(makeFieldCard(title: "Сумма в тенге", content: amountField))
        stackView.addArrangedSubview(makeFieldCard(title: "Категория", content: categoryButton))
        stackView.addArrangedSubview(makeFieldCard(title: "Описание", content: detailsView))

        merchantField.font = .systemFont(ofSize: 16, weight: .medium)
        merchantField.clearButtonMode = .whileEditing
        merchantField.returnKeyType = .next
        amountField.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        amountField.keyboardType = .numbersAndPunctuation
        detailsView.font = .systemFont(ofSize: 15)
        detailsView.backgroundColor = .clear
        detailsView.isScrollEnabled = false
        detailsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true

        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .large
        configuration.imagePlacement = .leading
        configuration.imagePadding = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 13, bottom: 12, trailing: 13)
        categoryButton.configuration = configuration
        categoryButton.contentHorizontalAlignment = .leading
        categoryButton.showsMenuAsPrimaryAction = true
        rebuildCategoryMenu()
    }

    private func populate() {
        merchantField.text = original.merchant
        amountField.text = String(format: "%.2f", original.amount)
            .replacingOccurrences(of: ".00", with: "")
        detailsView.text = original.details
    }

    private func makeSummaryCard() -> UIView {
        let card = UIView()
        let icon = UIImageView(image: UIImage(systemName: "pencil.and.list.clipboard"))
        let title = UILabel()
        let subtitle = UILabel()
        [card, icon, title, subtitle].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        FinLitTheme.styleCard(card, radius: 20)
        icon.tintColor = FinLitTheme.accent
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        title.text = "Всё под вашим контролем"
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.numberOfLines = 0
        subtitle.text = "Исправьте сумму или категорию. Мы запомним категорию для этого продавца. Минус в сумме означает расход, плюс — доход."
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        card.addSubview(icon)
        card.addSubview(title)
        card.addSubview(subtitle)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 17),
            icon.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            icon.widthAnchor.constraint(equalToConstant: 30),
            icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -17),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17),
        ])
        return card
    }

    private func makeFieldCard(title: String, content: UIView) -> UIView {
        let card = UIView()
        let label = UILabel()
        card.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        FinLitTheme.styleCard(card, radius: 18)
        label.text = title.uppercased()
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabel
        card.addSubview(label)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 7),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13),
            content.heightAnchor.constraint(greaterThanOrEqualToConstant: 38),
        ])
        return card
    }

    private func rebuildCategoryMenu() {
        let actions = TxCategory.allCases.map { category in
            UIAction(
                title: category.rawValue,
                image: UIImage(systemName: category.icon),
                state: category == selectedCategory ? .on : .off
            ) { [weak self] _ in
                self?.selectedCategory = category
                self?.rebuildCategoryMenu()
            }
        }
        categoryButton.menu = UIMenu(title: "Выберите категорию", children: actions)
        categoryButton.configuration?.title = selectedCategory.rawValue
        categoryButton.configuration?.image = UIImage(systemName: selectedCategory.icon)
        categoryButton.configuration?.baseForegroundColor = selectedCategory.uiColor
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func save() {
        let merchant = (merchantField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let details = detailsView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountText = (amountField.text ?? "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !merchant.isEmpty, let amount = Double(amountText), amount.isFinite,
              amount != 0, abs(amount) <= 1_000_000_000_000 else {
            errorLabel.text = "Укажите название и ненулевую сумму операции."
            errorLabel.isHidden = false
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        let updated = original.edited(
            merchant: merchant,
            details: details.isEmpty ? "—" : details,
            amount: amount,
            category: selectedCategory
        )
        AppStorage.shared.updateTransaction(updated, learnCategory: true)
        onSave(updated)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true)
    }
}
