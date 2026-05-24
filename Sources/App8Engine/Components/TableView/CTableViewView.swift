//
//  CTableViewView.swift
//  App8Engine
//
//  Static grouped table view component.
//  All sections and rows are pre-rendered once from inline DSL children.
//

import UIKit

@MainActor
class CTableViewView: App8BaseView<DSL.Model.Component.TableView.Content>, CViewProtocol {

    // MARK: - CViewProtocol

    weak var materialView: MaterialView?
    let contentView = UIView()

    // MARK: - Private

    private var viewModel: CTableViewViewModel?
    private var tableView: UITableView?

    /// Pre-rendered container views indexed by [sectionIndex][rowIndex].
    private var renderedRows: [[UIView]] = []

    // MARK: - Setup

    override func setup() {
        super.setup()
        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }

    // MARK: - Configure

    func configure(viewModel: CTableViewViewModel, superview: UIView? = nil, animated: Bool = false) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else { return }
        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)
        buildTableView(viewModel: viewModel)
    }

    // MARK: - Style

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
    }

    // MARK: - Table Construction

    private func buildTableView(viewModel: CTableViewViewModel) {
        tableView?.removeFromSuperview()
        tableView = nil
        renderedRows = []

        let props = viewModel.component.properties
        let tableStyle = props.tableStyle?.ui ?? .insetGrouped
        let tv = UITableView(frame: .zero, style: tableStyle)
        tv.backgroundColor = .clear
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.showsVerticalScrollIndicator = props.showsIndicator ?? true
        tv.showsHorizontalScrollIndicator = false
        tv.separatorStyle = .singleLine
        tv.separatorColor = UIColor.white.withAlphaComponent(0.12)
        let sepInset = props.separatorInset ?? 0
        tv.separatorInset = UIEdgeInsets(top: 0, left: sepInset, bottom: 0, right: 0)

        // Empty footer removes the extra bottom inset insetGrouped adds.
        tv.tableFooterView = UIView()

        tv.register(CTableViewCell.self, forCellReuseIdentifier: CTableViewCell.reuseId)
        tv.delegate = self
        tv.dataSource = self

        contentView.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: contentView.topAnchor),
            tv.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tv.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
        self.tableView = tv

        renderedRows = viewModel.component.sections.map { section in
            section.rows.map { row in
                let container = UIView()
                container.backgroundColor = .clear
                row.children.forEach { child in
                    viewModel.service.renderComponent(
                        child,
                        superview: container,
                        parentPath: viewModel.componentPath + "." + row.id,
                        parentVariableStore: viewModel.variableStore
                    )
                }
                return container
            }
        }

        tv.reloadData()
    }
}

// MARK: - UITableViewDataSource

extension CTableViewView: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel?.component.sections.count ?? 0
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel?.component.sections[safe: section]?.rows.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: CTableViewCell.reuseId, for: indexPath) as? CTableViewCell else {
            return UITableViewCell()
        }
        let row = viewModel?.component.sections[safe: indexPath.section]?.rows[safe: indexPath.row]
        cell.backgroundColor = row?.clearBackground == true ? .clear : UIColor.secondarySystemGroupedBackground
        if let rowView = renderedRows[safe: indexPath.section]?[safe: indexPath.row] {
            cell.setRenderedView(rowView)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel?.component.sections[safe: section]?.header
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        viewModel?.component.sections[safe: section]?.footer
    }
}

// MARK: - UITableViewDelegate

extension CTableViewView: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let height = viewModel?.component.sections[safe: indexPath.section]?.rows[safe: indexPath.row]?.height
        return height ?? UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let row = viewModel?.component.sections[safe: indexPath.section]?.rows[safe: indexPath.row],
              let actions = row.actions?[.tap] else { return }
        for action in actions {
            viewModel?.executeAction(action)
        }
    }
}

// MARK: - Array safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
