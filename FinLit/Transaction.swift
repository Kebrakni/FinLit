import UIKit

// MARK: - TxCategory UIKit colors

extension TxCategory {
    var uiColor: UIColor {
        switch self {
        case .food:              return UIColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .cafes:             return UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .transport:         return UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1)
        case .entertainment:     return UIColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1)
        case .health:            return UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        case .education:         return UIColor(red: 0.00, green: 0.64, blue: 0.91, alpha: 1)
        case .utilities:         return UIColor(red: 1.00, green: 0.75, blue: 0.00, alpha: 1)
        case .subscriptions:     return UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1)
        case .shopping:          return UIColor(red: 1.00, green: 0.30, blue: 0.56, alpha: 1)
        case .loans:             return UIColor(red: 0.72, green: 0.15, blue: 0.10, alpha: 1)
        case .taxes:             return UIColor(red: 0.55, green: 0.55, blue: 0.57, alpha: 1)
        case .cashWithdrawals:   return UIColor(red: 0.18, green: 0.62, blue: 0.45, alpha: 1)
        case .transfers:         return UIColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1)
        case .internalTransfers: return UIColor(red: 0.48, green: 0.75, blue: 0.99, alpha: 1)
        case .other:             return UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)
        }
    }
}

// MARK: - TransactionCell

final class TransactionCell: UITableViewCell {

    private let cardView      = UIView()
    private let categoryBar   = UIView()
    private let iconView      = UIImageView()
    private let titleLabel    = UILabel()
    private let categoryLabel = UILabel()
    private let dateLabel     = UILabel()
    private let amountLabel   = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none

        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.backgroundColor = .secondarySystemBackground
        cardView.layer.cornerRadius = 16

        categoryBar.translatesAutoresizingMaskIntoConstraints = false
        categoryBar.layer.cornerRadius = 2.5

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 2

        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        categoryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        categoryLabel.textColor = .secondaryLabel

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .tertiaryLabel

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 16, weight: .bold)
        amountLabel.textAlignment = .right
        amountLabel.setContentHuggingPriority(.required, for: .horizontal)
        amountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        contentView.addSubview(cardView)
        cardView.addSubview(categoryBar)
        cardView.addSubview(iconView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(categoryLabel)
        cardView.addSubview(dateLabel)
        cardView.addSubview(amountLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            categoryBar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            categoryBar.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            categoryBar.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),
            categoryBar.widthAnchor.constraint(equalToConstant: 4),

            iconView.leadingAnchor.constraint(equalTo: categoryBar.trailingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            categoryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            categoryLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            categoryLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            dateLabel.topAnchor.constraint(equalTo: categoryLabel.bottomAnchor, constant: 2),
            dateLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            dateLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            amountLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            amountLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -14),
        ])
    }

    func configure(with tx: Transaction, date: String, amount: String) {
        titleLabel.text = tx.merchant
        categoryLabel.text = tx.category.rawValue
        dateLabel.text = date
        amountLabel.text = amount
        amountLabel.textColor = tx.amount < 0 ? .systemRed : .systemGreen

        let color = tx.category.uiColor
        categoryBar.backgroundColor = color
        iconView.image = UIImage(systemName: tx.category.icon)
        iconView.tintColor = color
    }
}
