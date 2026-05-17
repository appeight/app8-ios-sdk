import UIKit

final class DebugColorStyleView: UIView {

    // MARK: - UI Elements

    private let containerView: UIView = {
        let view = UIView()
        view.layer.cornerRadius = 10
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }()

    private let lightColorView: UIView = {
        let view = UIView()
        return view
    }()

    private let darkColorView: UIView = {
        let view = UIView()
        return view
    }()

    private let lightLabel: UILabel = {
        let label = UILabel()
        label.text = "light"
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.black.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let darkLabel: UILabel = {
        let label = UILabel()
        label.text = "dark"
        label.font = UIFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(containerView)
        containerView.addSubview(lightColorView)
        containerView.addSubview(darkColorView)
        addSubview(lightLabel)
        addSubview(darkLabel)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        lightColorView.translatesAutoresizingMaskIntoConstraints = false
        darkColorView.translatesAutoresizingMaskIntoConstraints = false
        lightLabel.translatesAutoresizingMaskIntoConstraints = false
        darkLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    // MARK: - Configuration

    /// Returns "#FFFFFF" for opaque colors, "#FFFFFF, 10%" for colors with alpha.
    private func formatHexWithAlpha(_ hex: DSL.Model.Style.Color.Hex) -> String {
        // hex.value is stored without # and may be 6 chars (RRGGBB) or 8 chars (RRGGBBAA)
        var hexString = hex.value

        if hexString.count == 8 {
            hexString = String(hexString.prefix(6))
        }

        let result = "#\(hexString)"

        // Epsilon guard for floating-point alpha comparison
        if hex.a < 0.999 {
            let alphaPercent = Int(round(hex.a * 100))
            return "\(result), \(alphaPercent)%"
        }

        return result
    }

    func configure(with color: DSL.Model.Style.Color.Themed) {
        lightColorView.constraints.forEach { $0.isActive = false }
        darkColorView.constraints.forEach { $0.isActive = false }

        let hasLight = color.light != nil
        let hasDark = color.dark != nil
        let hasThemePrefix = color.source == .themed

        if let lightHex = color.light {
            let comps: [String?] = [
                hasThemePrefix ? "light" : nil,
                formatHexWithAlpha(lightHex)
            ]
            lightLabel.text = comps.compactMap { $0 }.joined(separator: "\n")
            if let textColor = makeLabelColor(forStyleColor: color.light?.ui) {
                lightLabel.textColor = textColor
            }
        } else {
            lightLabel.text = nil
        }
        if let darkHex = color.dark {
            let comps: [String?] = [
                hasThemePrefix ? "dark" : nil,
                formatHexWithAlpha(darkHex)
            ]
            darkLabel.text = comps.compactMap { $0 }.joined(separator: "\n")
            if let textColor = makeLabelColor(forStyleColor: color.dark?.ui) {
                darkLabel.textColor = textColor
            }
        } else {
            darkLabel.text = nil
        }

        if hasLight && hasDark {
            lightColorView.isHidden = false
            darkColorView.isHidden = false
            lightLabel.isHidden = false
            darkLabel.isHidden = false

            lightColorView.backgroundColor = color.light?.ui
            darkColorView.backgroundColor = color.dark?.ui

            NSLayoutConstraint.activate([
                lightColorView.topAnchor.constraint(equalTo: containerView.topAnchor),
                lightColorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                lightColorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                lightColorView.widthAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 0.5),

                darkColorView.topAnchor.constraint(equalTo: containerView.topAnchor),
                darkColorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                darkColorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                darkColorView.widthAnchor.constraint(equalTo: containerView.widthAnchor, multiplier: 0.5),

                lightLabel.bottomAnchor.constraint(equalTo: lightColorView.bottomAnchor, constant: -6),
                lightLabel.leadingAnchor.constraint(equalTo: lightColorView.leadingAnchor, constant: 6),

                darkLabel.bottomAnchor.constraint(equalTo: darkColorView.bottomAnchor, constant: -6),
                darkLabel.centerXAnchor.constraint(equalTo: darkColorView.leadingAnchor, constant: 6)
            ])
        } else {
            lightLabel.isHidden = true
            darkLabel.isHidden = true

            if hasLight {
                lightLabel.isHidden = false
                lightColorView.isHidden = false
                darkColorView.isHidden = true
                lightColorView.backgroundColor = color.light?.ui

                NSLayoutConstraint.activate([
                    lightColorView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    lightColorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    lightColorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    lightColorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                    
                    lightLabel.bottomAnchor.constraint(equalTo: lightColorView.bottomAnchor, constant: -4),
                    lightLabel.leadingAnchor.constraint(equalTo: lightColorView.leadingAnchor, constant: 4)
                ])
            } else if hasDark {
                darkLabel.isHidden = false
                lightColorView.isHidden = true
                darkColorView.isHidden = false
                darkColorView.backgroundColor = color.dark?.ui

                NSLayoutConstraint.activate([
                    darkColorView.topAnchor.constraint(equalTo: containerView.topAnchor),
                    darkColorView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                    darkColorView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                    darkColorView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
                    
                    darkLabel.bottomAnchor.constraint(equalTo: darkColorView.bottomAnchor, constant: -4),
                    darkLabel.centerXAnchor.constraint(equalTo: darkColorView.leadingAnchor, constant: 4)
                ])
            }
        }
    }
    
    private func makeLabelColor(forStyleColor color: UIColor?) -> UIColor? {
        guard let color else { return nil }
        return (color.withAlphaComponent(1.0).isLight ? UIColor.black : UIColor.white).withAlphaComponent(0.7)
    }
}
