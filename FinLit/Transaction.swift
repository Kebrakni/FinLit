import UIKit

final class TransactionCell: UITableViewCell {

    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let dateLabel = UILabel()
    private let amountLabel = UILabel()

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
        cardView.layer.cornerRadius = 18

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.numberOfLines = 2

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 13)
        dateLabel.textColor = .secondaryLabel

        amountLabel.translatesAutoresizingMaskIntoConstraints = false
        amountLabel.font = .systemFont(ofSize: 16, weight: .bold)
        amountLabel.textAlignment = .right

        contentView.addSubview(cardView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(dateLabel)
        cardView.addSubview(amountLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: amountLabel.leadingAnchor, constant: -8),

            dateLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            dateLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -12),

            amountLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            amountLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16)
        ])
    }

    func configure(with tx: Transaction, date: String, amount: String) {
        titleLabel.text = tx.merchant
        dateLabel.text = date
        amountLabel.text = amount
        amountLabel.textColor = tx.amount < 0 ? .systemRed : .systemGreen
    }
}

