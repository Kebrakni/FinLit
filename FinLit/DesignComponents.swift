import UIKit

// Shared form surfaces keep the goal, savings and battle flows consistent.
enum FinLitDisplay {
    static func money(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_KZ")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0") ₸"
    }

    static func amount(_ text: String?) -> Double? {
        let normalized = (text ?? "")
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value > 0, value <= 1_000_000_000_000 else { return nil }
        return value
    }
}

final class FinLitFormField: UIView {
    let input = UITextField()

    init(title: String, placeholder: String, value: String = "", amount: Bool = false) {
        super.init(frame: .zero)
        FinLitTheme.styleCard(self, radius: 20)
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabel
        input.placeholder = placeholder
        input.text = value
        input.font = amount
            ? .monospacedDigitSystemFont(ofSize: 30, weight: .bold)
            : .systemFont(ofSize: 18, weight: .semibold)
        input.adjustsFontSizeToFitWidth = true
        input.minimumFontSize = 16
        input.clearButtonMode = .whileEditing
        input.keyboardType = amount ? .decimalPad : .default
        input.returnKeyType = .done
        input.addAction(UIAction { [weak input] _ in input?.resignFirstResponder() }, for: .editingDidEndOnExit)
        input.accessibilityLabel = title
        let stack = UIStackView(arrangedSubviews: [label, input])
        stack.axis = .vertical
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            input.heightAnchor.constraint(greaterThanOrEqualToConstant: amount ? 42 : 32)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

class FinLitFormSheet: UIViewController {
    let contentStack = UIStackView()
    let submitButton = UIButton(type: .system)
    private let scrollView = UIScrollView()
    private let errorLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let heading: String
    private let detail: String
    private let symbol: String
    private let actionTitle: String
    private let actionSymbol: String

    init(title: String, detail: String, symbol: String, action: String, actionSymbol: String = "checkmark") {
        heading = title
        self.detail = detail
        self.symbol = symbol
        actionTitle = action
        self.actionSymbol = actionSymbol
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 32
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = FinLitTheme.background
        view.tintColor = FinLitTheme.accent
        let close = closeButton
        var closeConfig = UIButton.Configuration.gray()
        closeConfig.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .bold))
        closeConfig.baseForegroundColor = .secondaryLabel
        closeConfig.cornerStyle = .capsule
        close.configuration = closeConfig
        close.accessibilityLabel = "Закрыть"
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .touchUpInside)

        scrollView.keyboardDismissMode = .interactive
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        contentStack.axis = .vertical
        contentStack.spacing = 16
        let dock = UIView()
        dock.backgroundColor = FinLitTheme.background
        let dockStack = UIStackView(arrangedSubviews: [errorLabel, submitButton])
        dockStack.axis = .vertical
        dockStack.spacing = 8
        errorLabel.font = .systemFont(ofSize: 13, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        FinLitTheme.configurePrimaryButton(submitButton, title: actionTitle, image: actionSymbol)
        submitButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        [close, scrollView, contentStack, dock, dockStack].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(close)
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(dock)
        dock.addSubview(dockStack)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            close.widthAnchor.constraint(equalToConstant: 36),
            close.heightAnchor.constraint(equalToConstant: 36),
            scrollView.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: dock.topAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dock.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            dockStack.topAnchor.constraint(equalTo: dock.topAnchor, constant: 12),
            dockStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            dockStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            dockStack.bottomAnchor.constraint(equalTo: dock.bottomAnchor, constant: -12),
            submitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54)
        ])
        addHeader()
        NotificationCenter.default.addObserver(
            self, selector: #selector(revealFocusedField),
            name: UIResponder.keyboardDidShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(revealFocusedField),
            name: UITextField.textDidBeginEditingNotification, object: nil
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func revealFocusedField() {
        view.layoutIfNeeded()
        func focused(in parent: UIView) -> UIView? {
            if parent.isFirstResponder { return parent }
            return parent.subviews.lazy.compactMap { focused(in: $0) }.first
        }
        guard let input = focused(in: contentStack) else { return }
        let rect = input.convert(input.bounds, to: scrollView).insetBy(dx: 0, dy: -24)
        scrollView.scrollRectToVisible(rect, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func addHeader() {
        let iconTile = FinLitGradientView()
        iconTile.layer.cornerRadius = 20
        iconTile.clipsToBounds = true
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = .init(pointSize: 25, weight: .semibold)
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconTile.addSubview(icon)
        NSLayoutConstraint.activate([
            iconTile.widthAnchor.constraint(equalToConstant: 60),
            iconTile.heightAnchor.constraint(equalToConstant: 60),
            icon.centerXAnchor.constraint(equalTo: iconTile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconTile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28)
        ])
        let iconRow = UIStackView(arrangedSubviews: [iconTile, UIView()])
        let title = UILabel()
        title.text = heading
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.numberOfLines = 0
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        let subtitle = UILabel()
        subtitle.text = detail
        subtitle.font = .systemFont(ofSize: 15)
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        [iconRow, title, subtitle].forEach { contentStack.addArrangedSubview($0) }
        contentStack.setCustomSpacing(18, after: iconRow)
        contentStack.setCustomSpacing(8, after: title)
        contentStack.setCustomSpacing(24, after: subtitle)
    }

    func submit() {}

    func showError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
        if message != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    func setLoading(_ loading: Bool) {
        submitButton.configuration?.showsActivityIndicator = loading
        submitButton.isEnabled = !loading
        contentStack.isUserInteractionEnabled = !loading
        closeButton.isEnabled = !loading
        isModalInPresentation = loading
    }

    func finish(completion: (() -> Void)? = nil) {
        view.endEditing(true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(animated: true, completion: completion)
    }

    func addNote(_ text: String, symbol: String = "info.circle") {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = FinLitTheme.accent
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.alignment = .top
        row.spacing = 10
        contentStack.addArrangedSubview(row)
    }
}

final class StatementImportSheet: FinLitFormSheet {
    var onChooseFile: (() -> Void)?

    init() {
        super.init(
            title: "Выписка для Tengely",
            detail: "Поддерживается только оригинальная PDF-выписка Kaspi Gold на английском языке, с колонками Date, Amount, Transaction и Details.",
            symbol: "doc.text.magnifyingglass",
            action: "Выбрать PDF",
            actionSymbol: "folder"
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        addNote("В банковском приложении откройте карту → «Выписка» и выберите нужный период.", symbol: "1.circle.fill")
        addNote("При формировании выписки выберите English / Английский.", symbol: "2.circle.fill")
        addNote("Сохраните PDF через «Поделиться» → «Сохранить в Файлы», затем выберите его здесь.", symbol: "3.circle.fill")
        addNote("Выписки других банков, фото и скриншоты пока не поддерживаются.")
    }

    override func submit() {
        let chooseFile = onChooseFile
        dismiss(animated: true) { chooseFile?() }
    }
}

final class GoalEditorSheet: FinLitFormSheet {
    private var goal: Goal
    private let onSave: (Goal) -> Void
    private let nameField: FinLitFormField
    private let amountField: FinLitFormField
    private let deadlineSwitch = UISwitch()
    private let datePicker = UIDatePicker()

    init(goal: Goal, onSave: @escaping (Goal) -> Void) {
        self.goal = goal
        self.onSave = onSave
        nameField = FinLitFormField(title: "На что копим", placeholder: "Например, путешествие", value: goal.title)
        amountField = FinLitFormField(title: "Стоимость цели · ₸", placeholder: "350 000", value: String(format: "%.2f", goal.targetAmount).replacingOccurrences(of: ".00", with: ""), amount: true)
        super.init(title: "Ближе к мечте", detail: "Назовите цель и сумму. Каждый шаг к ней будет виден на главном экране.", symbol: "target", action: "Сохранить цель")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(nameField)
        contentStack.addArrangedSubview(amountField)
        let dateTitle = UILabel()
        dateTitle.text = "Накопить к дате"
        dateTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        deadlineSwitch.isOn = goal.deadline != nil
        deadlineSwitch.onTintColor = FinLitTheme.accent
        deadlineSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.datePicker.isHidden = !self.deadlineSwitch.isOn
        }, for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [dateTitle, deadlineSwitch])
        row.alignment = .center
        row.spacing = 12
        contentStack.addArrangedSubview(row)
        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .inline
        datePicker.locale = Locale(identifier: "ru_RU")
        datePicker.date = goal.deadline ?? Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        datePicker.isHidden = !deadlineSwitch.isOn
        contentStack.addArrangedSubview(datePicker)
        addNote("Уже накопленные деньги сохранятся, даже если изменить название или стоимость цели.", symbol: "lock.shield")
    }

    override func submit() {
        let name = (nameField.input.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showError("Дайте цели название."); return }
        guard let amount = FinLitDisplay.amount(amountField.input.text) else {
            showError("Введите стоимость цели больше нуля."); return
        }
        goal.title = name
        goal.targetAmount = amount
        goal.deadline = deadlineSwitch.isOn ? datePicker.date : nil
        onSave(goal)
        finish()
    }
}

final class SavingsContributionSheet: FinLitFormSheet {
    private let goal: Goal
    private let saved: Double
    private let onSave: (Double) -> Void
    private let amountField = FinLitFormField(title: "Сумма накопления · ₸", placeholder: "0", amount: true)
    private let previewTitle = UILabel()
    private let previewDetail = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)

    init(goal: Goal, saved: Double, onSave: @escaping (Double) -> Void) {
        self.goal = goal
        self.saved = saved
        self.onSave = onSave
        super.init(title: "Ещё один шаг", detail: "Добавьте деньги, которые отложили на «\(goal.title)».", symbol: "plus.circle.fill", action: "Добавить накопление", actionSymbol: "plus")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(amountField)
        amountField.input.addAction(UIAction { [weak self] _ in self?.updatePreview() }, for: .editingChanged)
        let quickAmounts = UIStackView()
        quickAmounts.spacing = 8
        quickAmounts.distribution = .fillEqually
        [1000, 5000, 10000].forEach { amount in
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.tinted()
            config.title = FinLitDisplay.money(Double(amount))
            config.baseForegroundColor = FinLitTheme.accent
            config.cornerStyle = .capsule
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
                var result = attributes
                result.font = .systemFont(ofSize: 13, weight: .semibold)
                return result
            }
            button.configuration = config
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            button.addAction(UIAction { [weak self] _ in
                self?.amountField.input.text = String(amount)
                self?.showError(nil)
                self?.updatePreview()
                UISelectionFeedbackGenerator().selectionChanged()
            }, for: .touchUpInside)
            quickAmounts.addArrangedSubview(button)
        }
        contentStack.addArrangedSubview(quickAmounts)
        let preview = UIView()
        FinLitTheme.styleCard(preview)
        previewTitle.font = .monospacedDigitSystemFont(ofSize: 23, weight: .bold)
        previewTitle.numberOfLines = 0
        previewDetail.font = .systemFont(ofSize: 13)
        previewDetail.textColor = .secondaryLabel
        previewDetail.numberOfLines = 0
        progress.progressTintColor = FinLitTheme.accent
        progress.trackTintColor = FinLitTheme.accentSoft
        progress.layer.cornerRadius = 4
        progress.clipsToBounds = true
        progress.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let stack = UIStackView(arrangedSubviews: [previewTitle, progress, previewDetail])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        preview.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: preview.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -20)
        ])
        contentStack.addArrangedSubview(preview)
        addNote("Для наличных и других накоплений вне выписки. Деньги, уже учтённые из выписки, добавлять повторно не нужно.", symbol: "banknote")
        updatePreview()
    }

    private func updatePreview() {
        let amount = FinLitDisplay.amount(amountField.input.text) ?? 0
        let total = saved + amount
        let fraction = min(max(total / max(goal.targetAmount, 1), 0), 1)
        previewTitle.text = FinLitDisplay.money(total)
        progress.setProgress(Float(fraction), animated: !UIAccessibility.isReduceMotionEnabled)
        previewDetail.text = "\(Int(fraction * 100))% цели · \(total >= goal.targetAmount ? "цель достигнута!" : "осталось \(FinLitDisplay.money(goal.targetAmount - total))")"
    }

    override func submit() {
        guard let amount = FinLitDisplay.amount(amountField.input.text) else {
            showError("Введите сумму накопления больше нуля."); return
        }
        guard goal.savedAmount + amount <= Transaction.maximumAmount else {
            showError("Общая сумма накоплений слишком велика. Проверьте введённую сумму."); return
        }
        onSave(amount)
        finish()
    }
}

/// Single-field sheets also support asynchronous submissions, retaining the input on errors.
final class FinLitInputSheet: FinLitFormSheet {
    let field: FinLitFormField
    var onSubmit: ((FinLitInputSheet) -> Void)?

    init(title: String, detail: String, symbol: String, action: String, fieldTitle: String,
         placeholder: String, value: String = "", amount: Bool = false) {
        field = FinLitFormField(title: fieldTitle, placeholder: placeholder, value: value, amount: amount)
        super.init(title: title, detail: detail, symbol: symbol, action: action, actionSymbol: "arrow.right")
        sheetPresentationController?.detents = [
            .custom(identifier: .init("inputForm")) { min(610, $0.maximumDetentValue) }, .large()
        ]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        contentStack.addArrangedSubview(field)
        field.input.addAction(UIAction { [weak self] _ in self?.showError(nil) }, for: .editingChanged)
    }

    override func submit() { onSubmit?(self) }
}

final class FinLitNoticeSheet: FinLitFormSheet {
    init(title: String, detail: String, symbol: String = "info.circle.fill") {
        super.init(title: title, detail: detail, symbol: symbol, action: "Понятно")
        sheetPresentationController?.detents = [
            .custom(identifier: .init("notice")) { min(560, $0.maximumDetentValue) }, .large()
        ]
    }

    required init?(coder: NSCoder) { fatalError() }
    override func submit() { dismiss(animated: true) }
}

final class AnalyticsCategoryCell: UITableViewCell {
    private let tile = UIView()
    private let icon = UIImageView()
    private let name = UILabel()
    private let amount = UILabel()
    private let share = UILabel()
    private let meter = UIProgressView(progressViewStyle: .default)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = FinLitTheme.surface
        accessoryType = .disclosureIndicator
        selectionStyle = .default
        tile.layer.cornerRadius = 14
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = .init(pointSize: 18, weight: .semibold)
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.numberOfLines = 2
        amount.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        amount.setContentCompressionResistancePriority(.required, for: .horizontal)
        amount.setContentHuggingPriority(.required, for: .horizontal)
        share.font = .systemFont(ofSize: 12)
        share.textColor = .secondaryLabel
        meter.trackTintColor = .quaternarySystemFill
        meter.layer.cornerRadius = 2
        meter.clipsToBounds = true
        [tile, icon, name, amount, share, meter].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        contentView.addSubview(tile)
        tile.addSubview(icon)
        [name, amount, share, meter].forEach { contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            tile.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: 44),
            tile.heightAnchor.constraint(equalToConstant: 44),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            name.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 15),
            name.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 12),
            name.trailingAnchor.constraint(lessThanOrEqualTo: amount.leadingAnchor, constant: -10),
            amount.topAnchor.constraint(equalTo: name.topAnchor),
            amount.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            share.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 5),
            share.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            share.trailingAnchor.constraint(equalTo: amount.trailingAnchor),
            meter.topAnchor.constraint(equalTo: share.bottomAnchor, constant: 9),
            meter.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            meter.trailingAnchor.constraint(equalTo: amount.trailingAnchor),
            meter.heightAnchor.constraint(equalToConstant: 3),
            meter.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(category: TxCategory, value: Double, total: Double) {
        icon.image = UIImage(systemName: category.icon)
        icon.tintColor = category.uiColor
        tile.backgroundColor = category.uiColor.withAlphaComponent(0.13)
        name.text = category.rawValue
        amount.text = FinLitDisplay.money(abs(value))
        let fraction = total > 0 ? abs(value) / total : 0
        share.text = String(format: "%.0f%% от общей суммы", fraction * 100)
        meter.progressTintColor = category.uiColor
        meter.progress = Float(min(max(fraction, 0), 1))
    }
}

final class FinLitEmptyStateView: UIView {
    init(symbol: String, title: String, detail: String) {
        super.init(frame: .zero)
        let tile = UIView()
        tile.backgroundColor = FinLitTheme.accentSoft
        tile.layer.cornerRadius = 24
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = FinLitTheme.accent
        icon.preferredSymbolConfiguration = .init(pointSize: 28, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)
        NSLayoutConstraint.activate([
            tile.widthAnchor.constraint(equalToConstant: 76),
            tile.heightAnchor.constraint(equalToConstant: 76),
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 32),
            icon.heightAnchor.constraint(equalToConstant: 32)
        ])
        let heading = UILabel()
        heading.text = title
        heading.font = .systemFont(ofSize: 21, weight: .bold)
        heading.textAlignment = .center
        heading.numberOfLines = 0
        let subtitle = UILabel()
        subtitle.text = detail
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = .secondaryLabel
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [tile, heading, subtitle])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // A background view can be shorter than its content on compact screens;
        // scrolling the parent must remain possible without broken constraints.
        let center = stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        center.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 20),
            center,
            heading.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
