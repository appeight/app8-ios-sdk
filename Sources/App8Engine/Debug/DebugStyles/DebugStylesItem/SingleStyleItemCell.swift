import UIKit
import Combine

final class SingleStyleItemCell: UITableViewCell {

    static let reuseIdentifier = "SingleStyleItemCell"

    // MARK: - Publishers

    var onJsonTapped: AnyPublisher<(styleId: String, styleType: String, json: String), Never> {
        styleContentView.onJsonTapped.eraseToAnyPublisher()
    }

    // MARK: - UI Elements

    private let pointerIcon: UIImageView = {
        let imageView = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        imageView.image = UIImage(systemName: "staroflife.circle.fill", withConfiguration: config)
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let idLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 17, weight: .medium)
        label.textColor = .white
        return label
    }()

    private let typeLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.5)
        return label
    }()

    private let styleContentView = StyleContentView()

    // MARK: - Initialization

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(pointerIcon)
        contentView.addSubview(idLabel)
        contentView.addSubview(typeLabel)
        contentView.addSubview(styleContentView)

        pointerIcon.translatesAutoresizingMaskIntoConstraints = false
        idLabel.translatesAutoresizingMaskIntoConstraints = false
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        styleContentView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pointerIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            pointerIcon.centerYAnchor.constraint(equalTo: idLabel.centerYAnchor),
            pointerIcon.widthAnchor.constraint(equalToConstant: 22),
            pointerIcon.heightAnchor.constraint(equalToConstant: 22),

            idLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            idLabel.leadingAnchor.constraint(equalTo: pointerIcon.trailingAnchor, constant: 8),
            idLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            typeLabel.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 4),
            typeLabel.leadingAnchor.constraint(equalTo: idLabel.leadingAnchor),
            typeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            styleContentView.topAnchor.constraint(equalTo: typeLabel.bottomAnchor, constant: 10),
            styleContentView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            styleContentView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            styleContentView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    // MARK: - Configuration

    func configure(with viewModel: SingleStyleItemViewModelProtocol) {
        idLabel.text = viewModel.styleId
        typeLabel.text = "Type: \(viewModel.styleType)"
        styleContentView.configure(with: viewModel.style)

        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)

        if viewModel.style.isResolved() {
            pointerIcon.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)
            pointerIcon.tintColor = .systemGreen
        } else {
            pointerIcon.image = UIImage(systemName: "staroflife.circle.fill", withConfiguration: config)
            pointerIcon.tintColor = .systemBlue
        }

        pointerIcon.isHidden = false
    }
}
