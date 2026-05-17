import UIKit
import Combine

final class DebugStylesViewController: UIViewController {

    var viewModel: DebugStylesViewModelProtocol!

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()
    private var cellSubscriptions: [IndexPath: AnyCancellable] = [:]

    // MARK: - UI Elements

    private lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(ErrorStyleItemCell.self, forCellReuseIdentifier: ErrorStyleItemCell.reuseIdentifier)
        tableView.register(SingleStyleItemCell.self, forCellReuseIdentifier: SingleStyleItemCell.reuseIdentifier)
        tableView.register(ResolvedStyleItemCell.self, forCellReuseIdentifier: ResolvedStyleItemCell.reuseIdentifier)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    // MARK: Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setupBindings()
    }

    // MARK: Setup

    private func setupViews() {
        view.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupBindings() {
        guard let viewModel = viewModel as? DebugStylesViewModel else { return }

        viewModel.onJsonTapped
            .sink { [weak self] info in
                self?.presentJSONBottomSheet(styleId: info.styleId, styleType: info.styleType, json: info.json)
            }
            .store(in: &cancellables)
    }

    private func presentJSONBottomSheet(styleId: String, styleType: String, json: String) {
        let bottomSheet = DebugStyleJSONBottomSheet(styleId: styleId, styleType: styleType, jsonString: json)

        if let sheet = bottomSheet.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }

        present(bottomSheet, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension DebugStylesViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return viewModel.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return viewModel.sections[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        cellSubscriptions[indexPath]?.cancel()
        cellSubscriptions[indexPath] = nil

        let itemViewModel = viewModel.sections[indexPath.section][indexPath.row]
        guard let debugViewModel = viewModel as? DebugStylesViewModel else {
            return UITableViewCell()
        }

        switch itemViewModel.cellType {
        case .error:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ErrorStyleItemCell.reuseIdentifier,
                for: indexPath
            ) as? ErrorStyleItemCell,
                  let errorViewModel = itemViewModel as? ErrorStyleItemViewModelProtocol else {
                return UITableViewCell()
            }
            cell.configure(with: errorViewModel)
            return cell

        case .single:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: SingleStyleItemCell.reuseIdentifier,
                for: indexPath
            ) as? SingleStyleItemCell,
                  let singleViewModel = itemViewModel as? SingleStyleItemViewModelProtocol else {
                return UITableViewCell()
            }
            cell.configure(with: singleViewModel)

            let subscription = cell.onJsonTapped
                .sink { [weak debugViewModel] info in
                    debugViewModel?.onJsonTapped.send(info)
                }
            cellSubscriptions[indexPath] = subscription

            return cell

        case .resolved:
            guard let cell = tableView.dequeueReusableCell(
                withIdentifier: ResolvedStyleItemCell.reuseIdentifier,
                for: indexPath
            ) as? ResolvedStyleItemCell,
                  let resolvedViewModel = itemViewModel as? ResolvedStyleItemViewModelProtocol else {
                return UITableViewCell()
            }
            cell.configure(with: resolvedViewModel)

            let subscription = cell.onJsonTapped
                .sink { [weak debugViewModel] info in
                    debugViewModel?.onJsonTapped.send(info)
                }
            cellSubscriptions[indexPath] = subscription

            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension DebugStylesViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        headerView.backgroundColor = .clear

        let label = UILabel()
        label.text = "stylesheet #\(section)"
        label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.6)
        label.translatesAutoresizingMaskIntoConstraints = false

        headerView.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: headerView.bottomAnchor, constant: -8)
        ])

        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 40
    }
}
