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

    private lazy var dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "dd.MM.yyyy"
        return df
    }()

    private lazy var numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.register(TransactionCell.self, forCellReuseIdentifier: "TxCell")

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
        let cell = tableView.dequeueReusableCell(withIdentifier: "TxCell", for: indexPath) as! TransactionCell
        let tx = transactions[indexPath.row]
        let amount = "\(tx.amount < 0 ? "-" : "+")\(numberFormatter.string(from: NSNumber(value: abs(tx.amount))) ?? "0") ₸"
        cell.configure(with: tx, date: dateFormatter.string(from: tx.date), amount: amount)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        80
    }
}

