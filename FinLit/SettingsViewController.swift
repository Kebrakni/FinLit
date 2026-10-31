import UIKit

final class SettingsViewController: UITableViewController {
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Настройки"
        view.backgroundColor = FinLitTheme.background
        tableView.backgroundColor = FinLitTheme.background
        tableView.separatorColor = FinLitTheme.outline
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 90
        tableView.sectionHeaderTopPadding = 12
        tableView.contentInset.bottom = 24
        tableView.register(AppearanceOptionsCell.self, forCellReuseIdentifier: "Appearance")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        ["Оформление", "Аккаунт", "Выписки", "О приложении"][section]
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0: return "Выбор сохраняется. Режим «Как на iPhone» автоматически следует светлой или тёмной теме устройства."
        case 1: return "Привязка Apple и Google пока недоступна. Выписки, цели и история чата сохраняются на этом устройстве."
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "Appearance", for: indexPath) as! AppearanceOptionsCell
            cell.configure(selected: AppearanceManager.shared.choice) { [weak cell] choice in
                AppearanceManager.shared.select(choice)
                cell?.select(choice)
                UISelectionFeedbackGenerator().selectionChanged()
            }
            return cell
        }

        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = FinLitTheme.surface
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = FinLitTheme.font(16, weight: .semibold)
        content.textProperties.color = .label
        content.secondaryTextProperties.font = FinLitTheme.font(13, style: .subheadline)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 0
        content.directionalLayoutMargins = .init(top: 18, leading: 18, bottom: 18, trailing: 18)
        content.imageProperties.tintColor = FinLitTheme.accent
        content.imageProperties.maximumSize = CGSize(width: 28, height: 28)
        switch indexPath.section {
        case 1:
            content.text = UserDefaults.standard.string(forKey: "battle_my_name") ?? "Локальный профиль"
            content.secondaryText = "На этом iPhone"
            content.image = UIImage(systemName: "person.crop.circle")
            cell.accessoryType = .disclosureIndicator
        case 2:
            content.text = "Поддерживаемая выписка"
            content.secondaryText = "PDF на английском · карта Kaspi Gold"
            content.image = UIImage(systemName: "doc.text")
            cell.accessoryType = .disclosureIndicator
        default:
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
            content.text = "Tengely"
            content.secondaryText = "Личные финансы с ясной целью\nВерсия \(version) (\(build))"
            content.image = UIImage(systemName: "sparkles")
            cell.selectionStyle = .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 1:
            present(FinLitNoticeSheet(
                title: "Ваш профиль",
                detail: "Выписки, цели, оформление и история чата сохраняются на этом iPhone. В битвах используется ваш игровой профиль.\n\nApple и Google пока не подключены: вход и перенос данных между устройствами ещё недоступны."
            ), animated: true)
        case 2:
            present(FinLitNoticeSheet(
                title: "Как подготовить выписку",
                detail: "Сейчас поддерживается только оригинальная PDF-выписка по карте Kaspi Gold.\n\n1. Откройте карту → «Выписка» и выберите период.\n2. Выберите English / Английский.\n3. Сохраните PDF через «Поделиться» → «Сохранить в Файлы».\n4. В Аналитике нажмите «Добавить выписку».\n\nФото, скриншоты и выписки других банков пока не поддерживаются."
            ), animated: true)
        default: break
        }
    }
}

private final class AppearanceOptionsCell: UITableViewCell {
    private let options = UIStackView()
    private var buttons: [AppearanceChoice: AppearanceOptionButton] = [:]
    private var onSelect: ((AppearanceChoice) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        options.spacing = 10
        options.distribution = .fillEqually
        options.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(options)
        NSLayoutConstraint.activate([
            options.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            options.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            options.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            options.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
        ])
        for choice in AppearanceChoice.allCases {
            let button = AppearanceOptionButton(choice: choice)
            button.addAction(UIAction { [weak self] _ in self?.onSelect?(choice) }, for: .touchUpInside)
            buttons[choice] = button
            options.addArrangedSubview(button)
        }
        updateAxis()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: AppearanceOptionsCell, _: UITraitCollection) in
            cell.updateAxis()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(selected: AppearanceChoice, onSelect: @escaping (AppearanceChoice) -> Void) {
        self.onSelect = onSelect
        select(selected)
    }

    func select(_ choice: AppearanceChoice) {
        buttons.forEach { $0.value.isSelected = $0.key == choice }
    }

    private func updateAxis() {
        options.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
    }
}

private final class AppearanceOptionButton: UIButton {
    private let choice: AppearanceChoice
    private let name = UILabel()
    private let check = UIImageView()

    init(choice: AppearanceChoice) {
        self.choice = choice
        super.init(frame: .zero)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1.5
        let preview = AppearancePreviewView(choice: choice)
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isUserInteractionEnabled = false
        preview.layer.cornerRadius = 12
        preview.clipsToBounds = true
        name.text = choice.title
        name.font = FinLitTheme.font(12, weight: .semibold, style: .caption1)
        name.adjustsFontForContentSizeCategory = true
        name.textAlignment = .center
        name.numberOfLines = 0
        check.contentMode = .scaleAspectFit
        [name, check].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; $0.isUserInteractionEnabled = false }
        [preview, name, check].forEach { addSubview($0) }
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            preview.heightAnchor.constraint(equalToConstant: 76),
            name.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 10),
            name.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            name.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            name.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            check.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 6),
            check.centerXAnchor.constraint(equalTo: centerXAnchor),
            check.widthAnchor.constraint(equalToConstant: 20),
            check.heightAnchor.constraint(equalToConstant: 20),
            check.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        accessibilityLabel = choice.title
        accessibilityHint = choice.detail
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (button: AppearanceOptionButton, _: UITraitCollection) in
            button.updateSelection()
        }
        updateSelection()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isSelected: Bool { didSet { updateSelection() } }
    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.7 : 1 } }

    private func updateSelection() {
        backgroundColor = isSelected ? FinLitTheme.accentSoft : FinLitTheme.surface
        layer.borderColor = (isSelected ? FinLitTheme.accent : FinLitTheme.outline).resolvedColor(with: traitCollection).cgColor
        name.textColor = isSelected ? FinLitTheme.accent : .label
        check.image = UIImage(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        check.tintColor = isSelected ? FinLitTheme.accent : .tertiaryLabel
        accessibilityTraits = isSelected ? [.button, .selected] : [.button]
    }
}

/// A code-drawn preview stays sharp at any display scale and uses no assets.
private final class AppearancePreviewView: UIView {
    private let choice: AppearanceChoice
    init(choice: AppearanceChoice) { self.choice = choice; super.init(frame: .zero); isOpaque = false }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        func sample(dark: Bool) {
            (dark ? UIColor(red: 0.045, green: 0.055, blue: 0.08, alpha: 1) : UIColor(red: 0.94, green: 0.95, blue: 0.98, alpha: 1)).setFill()
            context.fill(rect)
            (dark ? UIColor.white.withAlphaComponent(0.10) : UIColor.white).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 7, dy: 9), cornerRadius: 7).fill()
            FinLitTheme.buttonFill.setFill()
            UIBezierPath(roundedRect: CGRect(x: 14, y: 17, width: max(rect.width - 28, 1), height: 13), cornerRadius: 4).fill()
            (dark ? UIColor(red: 0.63, green: 0.67, blue: 1, alpha: 1) : FinLitTheme.buttonFill.withAlphaComponent(0.55)).setFill()
            for (index, height) in [10.0, 18.0, 14.0, 25.0].enumerated() {
                let width = max((rect.width - 40) / 4, 3)
                let x = 14 + CGFloat(index) * (width + 4)
                UIBezierPath(roundedRect: CGRect(x: x, y: 60 - CGFloat(height), width: width, height: CGFloat(height)), cornerRadius: 2).fill()
            }
        }
        sample(dark: choice == .dark)
        if choice == .system {
            context.saveGState()
            context.clip(to: CGRect(x: rect.midX, y: 0, width: rect.width / 2, height: rect.height))
            sample(dark: true)
            context.restoreGState()
        }
    }
}
