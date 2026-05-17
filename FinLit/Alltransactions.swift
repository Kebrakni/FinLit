import UIKit

final class AllTransactionsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    // MARK: - Filter

    enum Filter: Int, CaseIterable {
        case all = 0, income, expense, purchases, transfers, replenishment, withdrawals, others

        var title: String {
            switch self {
            case .all:           return "Все"
            case .income:        return "Доходы"
            case .expense:       return "Расходы"
            case .purchases:     return "Покупки"
            case .transfers:     return "Переводы"
            case .replenishment: return "Пополнения"
            case .withdrawals:   return "Снятия"
            case .others:        return "Другое"
            }
        }
    }

    // MARK: - State

    private let all: [Transaction]
    private var filtered: [Transaction] = []
    private var selectedFilter: Filter = .all

    // MARK: - UI

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let filterScrollView = UIScrollView()
    private let filterStack = UIStackView()
    private var filterButtons: [UIButton] = []

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

    // MARK: - Init

    init(transactions: [Transaction]) {
        self.all = transactions.sorted { $0.date > $1.date }
        self.filtered = self.all
        super.init(nibName: nil, bundle: nil)
        title = "Все операции"
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupFilterBar()
        setupTableView()
    }

    // MARK: - Setup

    private func setupFilterBar() {
        filterScrollView.translatesAutoresizingMaskIntoConstraints = false
        filterScrollView.showsHorizontalScrollIndicator = false
        filterScrollView.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)

        filterStack.translatesAutoresizingMaskIntoConstraints = false
        filterStack.axis = .horizontal
        filterStack.spacing = 8
        filterStack.alignment = .center

        for filter in Filter.allCases {
            let btn = UIButton(type: .system)
            btn.setTitle(filter.title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            btn.layer.cornerRadius = 14
            btn.layer.borderWidth = 1.5
            btn.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            btn.tag = filter.rawValue
            btn.addTarget(self, action: #selector(filterTapped(_:)), for: .touchUpInside)
            filterStack.addArrangedSubview(btn)
            filterButtons.append(btn)
        }

        filterScrollView.addSubview(filterStack)
        view.addSubview(filterScrollView)

        NSLayoutConstraint.activate([
            filterScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            filterScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterScrollView.heightAnchor.constraint(equalToConstant: 40),

            filterStack.topAnchor.constraint(equalTo: filterScrollView.topAnchor),
            filterStack.bottomAnchor.constraint(equalTo: filterScrollView.bottomAnchor),
            filterStack.leadingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.leadingAnchor),
            filterStack.trailingAnchor.constraint(equalTo: filterScrollView.contentLayoutGuide.trailingAnchor),
            filterStack.heightAnchor.constraint(equalTo: filterScrollView.frameLayoutGuide.heightAnchor),
        ])

        updateFilterStyles()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground
        tableView.register(TransactionCell.self, forCellReuseIdentifier: "TxCell")

        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: filterScrollView.bottomAnchor, constant: 8),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Filter actions

    @objc private func filterTapped(_ sender: UIButton) {
        selectedFilter = Filter(rawValue: sender.tag) ?? .all
        applyFilter()
        updateFilterStyles()
    }

    private func applyFilter() {
        filtered = all.filter { tx in
            let text = tx.details.lowercased()
            switch selectedFilter {
            case .all:           return true
            case .income:        return tx.amount > 0
            case .expense:       return tx.amount < 0
            case .purchases:     return text.hasPrefix("purchases ")
            case .transfers:     return text.hasPrefix("transfers ")
            case .replenishment: return text.hasPrefix("replenishment ")
            case .withdrawals:   return text.hasPrefix("withdrawals ")
            case .others:        return text.hasPrefix("others ")
            }
        }
        tableView.reloadData()
    }

    private func updateFilterStyles() {
        for btn in filterButtons {
            let filter = Filter(rawValue: btn.tag) ?? .all
            let isSelected = filter == selectedFilter
            UIView.animate(withDuration: 0.15) {
                btn.backgroundColor = isSelected ? .systemBlue : .clear
                btn.setTitleColor(isSelected ? .white : .systemBlue, for: .normal)
                btn.layer.borderColor = UIColor.systemBlue.cgColor
            }
        }
    }

    // MARK: - TableView

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "TxCell", for: indexPath) as! TransactionCell
        let tx = filtered[indexPath.row]
        cell.configure(with: tx, date: dateFormatter.string(from: tx.date), amount: formattedAmount(tx.amount))
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        80
    }

    // MARK: - Formatting

    private func formattedAmount(_ value: Double) -> String {
        let s = numberFormatter.string(from: NSNumber(value: abs(value))) ?? "0"
        return "\(value < 0 ? "-" : "+")\(s) ₸"
    }
}
