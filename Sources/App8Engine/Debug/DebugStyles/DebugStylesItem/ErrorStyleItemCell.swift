import UIKit

final class ErrorStyleItemCell: UITableViewCell {

    static let reuseIdentifier = "ErrorStyleItemCell"

    // MARK: - UI Elements

    private let errorBackgroundView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.red.withAlphaComponent(0.1)
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        return view
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = UIColor.red.withAlphaComponent(0.9)
        label.numberOfLines = 0
        return label
    }()

    private let jsonLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.numberOfLines = 0
        return label
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        return stack
    }()

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

        contentView.addSubview(errorBackgroundView)
        errorBackgroundView.addSubview(stackView)

        stackView.addArrangedSubview(errorLabel)
        stackView.addArrangedSubview(jsonLabel)

        errorBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            errorBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            errorBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            errorBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            errorBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            stackView.topAnchor.constraint(equalTo: errorBackgroundView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: errorBackgroundView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: errorBackgroundView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: errorBackgroundView.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Configuration

    func configure(with viewModel: ErrorStyleItemViewModelProtocol) {
        errorLabel.text = "⚠️ Error: \(viewModel.errorMessage)"

        let formattedJson = formatJSON(viewModel.jsonData)
        jsonLabel.text = formattedJson
    }

    // MARK: - Helpers

    private func formatJSON(_ jsonString: String) -> String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return jsonString
        }
        return prettyString
    }
}
