import UIKit

final class AllTransactionsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    enum Filter: Int, CaseIterable {
        case all = 0, income, expense, purchases, transfers, replenishment, withdrawals, others

        var title: String {
            switch self {
            case .all: return "All"
            case .income: return "Income"
            case .expense: return "Expense"
            case .purchases: return "Purchases"
            case .transfers: return "Transfers"
            case .replenishment: return "Replenishment"
            case .withdrawals: return "Withdrawals"
            case .others: return "Others"
            }
        }
    }

    private let all: [Transaction]
    private var filtered: [Transaction] = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let control: UISegmentedControl = {
        let items = Filter.allCases.map { $0.title }
        let sc = UISegmentedControl(items: items)
        sc.selectedSegmentIndex = 0
        sc.translatesAutoresizingMaskIntoConstraints = false
        return sc
    }()

    init(transactions: [Transaction]) {
        self.all = transactions.sorted { $0.date > $1.date }
        self.filtered = self.all
        super.init(nibName: nil, bundle: nil)
        title = "Все операции"
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        control.addTarget(self, action: #selector(changeFilter), for: .valueChanged)

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self

        view.addSubview(control)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            control.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            control.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            control.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            tableView.topAnchor.constraint(equalTo: control.bottomAnchor, constant: 10),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func changeFilter() {
        let f = Filter(rawValue: control.selectedSegmentIndex) ?? .all

        filtered = all.filter { tx in
            let text = tx.details.lowercased()

            switch f {
            case .all: return true
            case .income: return tx.amount > 0
            case .expense: return tx.amount < 0
            case .purchases: return text.hasPrefix("purchases ")
            case .transfers: return text.hasPrefix("transfers ")
            case .replenishment: return text.hasPrefix("replenishment ")
            case .withdrawals: return text.hasPrefix("withdrawals ")
            case .others: return text.hasPrefix("others ")
            }
        }

        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let tx = filtered[indexPath.row]
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

