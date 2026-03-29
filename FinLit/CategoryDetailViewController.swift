// CategoryDetailViewController.swift (как у тебя, без изменений)
import UIKit

final class CategoryDetailViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    private let category: TxCategory
    private let transactions: [Transaction]
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(category: TxCategory, transactions: [Transaction]) {
        self.category = category
        self.transactions = transactions
        super.init(nibName: nil, bundle: nil)
        title = category.rawValue
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        transactions.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let tx = transactions[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.textLabel?.text = tx.merchant
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = "\(formatDate(tx.date)) • \(formatMoneySigned(tx.amount))"
        cell.detailTextLabel?.textColor = .secondaryLabel
        return cell
    }

    private func formatMoneySigned(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let absVal = abs(value)
        let s = formatter.string(from: NSNumber(value: absVal)) ?? "0"
        let sign = value < 0 ? "-" : "+"
        return "\(sign)\(s) ₸"
    }

    private func formatDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "dd.MM.yyyy"
        return df.string(from: d)
    }
}

