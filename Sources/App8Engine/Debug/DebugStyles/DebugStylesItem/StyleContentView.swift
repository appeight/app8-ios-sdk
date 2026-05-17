import UIKit
import Combine

final class StyleContentView: UIView {

    // MARK: - Publishers

    let onJsonTapped = PassthroughSubject<(styleId: String, styleType: String, json: String), Never>()

    // MARK: - Properties

    private var currentStyleId: String?
    private var currentStyleType: String?
    private var currentJsonString: String?

    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let jsonContentView: UIView = {
        let view = UIView()
        return view
    }()

    private let jsonLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.numberOfLines = 0
        return label
    }()

    private let gradientLayer: CAGradientLayer = {
        let gradient = CAGradientLayer()
        gradient.colors = [
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            UIColor.black.withAlphaComponent(0).cgColor
        ]
        gradient.locations = [Float]([0.0, 0.7, 1.0]).map { NSNumber(value: $0) }
        gradient.startPoint = .zero
        gradient.endPoint = CGPoint(x: 0, y: 1)
        return gradient
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(containerView)
        containerView.addSubview(jsonContentView)
        jsonContentView.addSubview(jsonLabel)
        jsonContentView.layer.mask = gradientLayer

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(containerTapped))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true

        containerView.translatesAutoresizingMaskIntoConstraints = false
        jsonContentView.translatesAutoresizingMaskIntoConstraints = false
        jsonLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.heightAnchor.constraint(equalToConstant: 100),

            jsonContentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            jsonContentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            jsonContentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            jsonContentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            jsonLabel.topAnchor.constraint(equalTo: jsonContentView.topAnchor, constant: 12),
            jsonLabel.leadingAnchor.constraint(equalTo: jsonContentView.leadingAnchor, constant: 12),
            jsonLabel.trailingAnchor.constraint(equalTo: jsonContentView.trailingAnchor, constant: -12)
        ])
    }

    // MARK: - Actions

    @objc private func containerTapped() {
        // Only emit event if JSON view is visible (unresolved pointer)
        guard !jsonContentView.isHidden,
              let styleId = currentStyleId,
              let styleType = currentStyleType,
              let json = currentJsonString else {
            return
        }

        onJsonTapped.send((styleId: styleId, styleType: styleType, json: json))
    }

    // MARK: - Configuration

    private static var renderSupportedFor: [DSL.Model.Style.SType] = [
        .key(.color)
    ]

    func configure(with style: DSL.Model.Style.`Any`) {
        currentStyleId = style.id
        switch style.type {
        case .key(let key):
            currentStyleType = key.rawValue
        case .custom(let customType):
            currentStyleType = customType
        }
        currentJsonString = style.jsonStringRepresentation

        // Clear existing content except jsonContentView
        containerView.subviews.forEach {
            if $0 !== jsonContentView {
                $0.removeFromSuperview()
            }
        }

        if style.isResolved(), Self.renderSupportedFor.contains(style.type) {
            jsonContentView.isHidden = true
            if let c: DSL.Model.Style.ConcreteEntity<DSL.Model.Style.Color.Themed> = style.asConcreteEntity() {
                let color = c.content
                let colorView = DebugColorStyleView()
                colorView.configure(with: color)
                containerView.addSubview(colorView)

                colorView.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    colorView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    colorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    colorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    colorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
                ])
            }
        } else {
            jsonContentView.isHidden = false
            jsonLabel.attributedText = JSONHighlighter.highlightedJSON(from: style.jsonStringRepresentation)
        }
    }
}
