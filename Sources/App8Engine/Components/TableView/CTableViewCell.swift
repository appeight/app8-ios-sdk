//
//  CTableViewCell.swift
//  App8Engine
//
//  A simple UITableViewCell that hosts a pre-rendered DSL view.
//

import UIKit

@MainActor
final class CTableViewCell: UITableViewCell {

    static let reuseId = "CTableViewCell"

    private(set) var renderedView: UIView?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .clear
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Attach a pre-rendered DSL view as the cell's content.
    func setRenderedView(_ view: UIView) {
        renderedView?.removeFromSuperview()
        renderedView = view
        contentView.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentView.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}
