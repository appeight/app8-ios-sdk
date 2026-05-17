//
//  CShapeView.swift
//  App8Engine
//

import UIKit
import Combine

class CShapeView: App8BaseView<DSL.Model.Component.Shape.C>, CViewProtocol {

    private var viewModel: CShapeViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    weak var materialView: MaterialView?
    let contentView = UIView()

    private let trackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()

    /// -1 sentinel forces an initial render even when progress starts at 0.
    private var lastProgress: CGFloat = -1

    private var propertiesCancellable: AnyCancellable?
    private var variablesCancellable: AnyCancellable?

    // MARK: - Setup

    override func setup() {
        super.setup()

        // contentView fills self (required by CViewProtocol / applyBaseStyle).
        addSubview(contentView)
        contentView.cMakeEqualToSuperview()
        contentView.isUserInteractionEnabled = false
        contentView.backgroundColor = .clear

        trackLayer.fillColor = UIColor.clear.cgColor
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeEnd = 0
        layer.addSublayer(trackLayer)
        layer.addSublayer(progressLayer)
    }

    // MARK: - Configure

    func configure(viewModel: CShapeViewModel, superview: UIView? = nil, animated: Bool = true) {
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

        applyCurrentProperties(animated: false)

        propertiesCancellable = viewModel.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties(animated: true)
            }

        variablesCancellable = viewModel.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties(animated: true)
            }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        rebuildPath()
    }

    // MARK: - Path

    private func rebuildPath() {
        guard let vm = viewModel else { return }
        let props = vm.currentProperties
        let lw = CGFloat(props.lineWidth ?? 8)

        let cap: CAShapeLayerLineCap
        switch props.lineCap {
        case .butt:   cap = .butt
        case .square: cap = .square
        default:      cap = .round
        }

        switch props.kind {
        case .arc:
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = max(0, (min(bounds.width, bounds.height) / 2) - lw / 2)
            let startAngleRad = CGFloat((props.startAngle ?? -90) * .pi / 180)
            let path = UIBezierPath(arcCenter: center, radius: radius,
                                    startAngle: startAngleRad,
                                    endAngle: startAngleRad + 2 * .pi,
                                    clockwise: true).cgPath
            trackLayer.isHidden = false
            trackLayer.frame = bounds; trackLayer.path = path
            trackLayer.lineWidth = CGFloat(props.trackLineWidth ?? props.lineWidth ?? 8)
            trackLayer.lineCap = cap
            progressLayer.frame = bounds; progressLayer.path = path
            progressLayer.lineWidth = lw; progressLayer.lineCap = cap
            progressLayer.fillColor = UIColor.clear.cgColor

        case .bar:
            let capOffset: CGFloat = (cap == .round || cap == .square) ? lw / 2 : 0
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: capOffset, y: bounds.midY))
            linePath.addLine(to: CGPoint(x: bounds.width - capOffset, y: bounds.midY))
            let path = linePath.cgPath
            trackLayer.isHidden = false
            trackLayer.frame = bounds; trackLayer.path = path
            trackLayer.lineWidth = CGFloat(props.trackLineWidth ?? props.lineWidth ?? 8)
            trackLayer.lineCap = cap
            progressLayer.frame = bounds; progressLayer.path = path
            progressLayer.lineWidth = lw; progressLayer.lineCap = cap
            progressLayer.fillColor = UIColor.clear.cgColor

        case .circle:
            let inset = lw / 2
            let path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
            trackLayer.isHidden = true
            progressLayer.frame = bounds; progressLayer.path = path
            progressLayer.lineWidth = lw; progressLayer.lineCap = cap
            // fillColor applied in applyCurrentProperties.

        case .line:
            let linePath = UIBezierPath()
            if bounds.width >= bounds.height {
                linePath.move(to: CGPoint(x: 0, y: bounds.midY))
                linePath.addLine(to: CGPoint(x: bounds.width, y: bounds.midY))
            } else {
                linePath.move(to: CGPoint(x: bounds.midX, y: 0))
                linePath.addLine(to: CGPoint(x: bounds.midX, y: bounds.height))
            }
            trackLayer.isHidden = true
            progressLayer.frame = bounds; progressLayer.path = linePath.cgPath
            progressLayer.lineWidth = lw; progressLayer.lineCap = cap
            progressLayer.fillColor = UIColor.clear.cgColor

        case .polyline:
            guard let points = props.points, !points.isEmpty else {
                trackLayer.isHidden = true
                progressLayer.path = nil
                break
            }
            let resolvedPoints = points.compactMap { pt -> CGPoint? in
                guard let rawX = vm.resolvePropertyToFloat(pt.x),
                      let rawY = vm.resolvePropertyToFloat(pt.y) else { return nil }
                let x = rawX <= 1 ? rawX * bounds.width : rawX
                let y = rawY <= 1 ? rawY * bounds.height : rawY
                return CGPoint(x: x, y: y)
            }
            guard resolvedPoints.count >= 2 else {
                trackLayer.isHidden = true
                progressLayer.path = nil
                break
            }

            let polyPath: UIBezierPath
            if props.smooth == true {
                polyPath = catmullRomPath(points: resolvedPoints, closed: props.closed == true)
            } else {
                polyPath = UIBezierPath()
                polyPath.move(to: resolvedPoints[0])
                for i in 1..<resolvedPoints.count {
                    polyPath.addLine(to: resolvedPoints[i])
                }
                if props.closed == true { polyPath.close() }
            }

            trackLayer.isHidden = true
            progressLayer.frame = bounds
            progressLayer.path = polyPath.cgPath
            progressLayer.lineWidth = lw
            progressLayer.lineCap = cap
            progressLayer.strokeEnd = 1
            progressLayer.fillColor = (props.closed == true && props.fillColor != nil)
                ? (UIColor(withHexString: props.fillColor!)?.resolvedColor(with: traitCollection).cgColor ?? UIColor.clear.cgColor)
                : UIColor.clear.cgColor

            // Apply stroke color here too so it survives a layoutSubviews rebuild.
            if let hex = props.strokeColor {
                progressLayer.strokeColor = UIColor(withHexString: hex)?
                    .resolvedColor(with: traitCollection).cgColor
            }
        }
    }

    // MARK: - Apply Properties

    private func applyCurrentProperties(animated: Bool) {
        guard let vm = viewModel else { return }

        if (viewModel?.service.context.layoutMode.isEnabled == true) {
            let gray = UIColor.black.withAlphaComponent(0.15).cgColor
            trackLayer.strokeColor = gray
            progressLayer.strokeColor = gray
            progressLayer.fillColor = UIColor.black.withAlphaComponent(0.1).cgColor
            progressLayer.strokeEnd = 1
            return
        }

        let props = vm.currentProperties

        switch props.kind {
        case .line:
            if let hex = props.strokeColor {
                progressLayer.strokeColor = UIColor(withHexString: hex)?
                    .resolvedColor(with: traitCollection).cgColor
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = 1
            CATransaction.commit()
            return  // no track, no progress animation

        case .circle:
            progressLayer.fillColor = props.fillColor
                .flatMap { UIColor(withHexString: $0) }?
                .resolvedColor(with: traitCollection).cgColor
                ?? UIColor.clear.cgColor
            if let hex = props.strokeColor {
                progressLayer.strokeColor = UIColor(withHexString: hex)?
                    .resolvedColor(with: traitCollection).cgColor
            }
            fallthrough  // share strokeEnd animation logic

        case .arc, .bar:
            if let hex = props.trackColor {
                trackLayer.strokeColor = UIColor(withHexString: hex)?
                    .resolvedColor(with: traitCollection).cgColor
            }
            if let hex = props.strokeColor {
                progressLayer.strokeColor = UIColor(withHexString: hex)?
                    .resolvedColor(with: traitCollection).cgColor
            }
            let progressExpr: String? = props.progress?.value
            let raw: CGFloat = progressExpr.flatMap { vm.resolvePropertyToFloat($0) } ?? 0
            let target = max(0, min(1, raw))
            guard target != lastProgress else { return }
            lastProgress = target
            if animated {
                // Per-property animation wins; otherwise fall back to the legacy
                // `animationDuration` / `animationCurve` siblings.
                let inline = props.progress?.animation?.inlineOrNil
                    ?? DSL.Model.Animation.Inline(
                        id: nil,
                        duration: props.animationDuration ?? 0.4,
                        delay: 0,
                        timing: namedCurve(from: props.animationCurve).map(DSL.Model.Animation.Timing.curve) ?? .curve(.easeOut),
                        options: []
                    )
                let anim = AnimationRunner.makeBasicAnimation(
                    keyPath: "strokeEnd",
                    from: progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd,
                    to: target,
                    animation: inline
                )
                anim.fillMode = .forwards
                anim.isRemovedOnCompletion = false
                progressLayer.add(anim, forKey: "strokeEnd")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = target
            CATransaction.commit()

        case .polyline:
            if let hex = props.strokeColor {
                progressLayer.strokeColor = UIColor(withHexString: hex)?
                    .resolvedColor(with: traitCollection).cgColor
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = 1
            CATransaction.commit()
            rebuildPath()
        }
    }

    // MARK: - Style Hook

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

    // MARK: - Helpers

    /// Generate a smooth Catmull-Rom spline path through the given points
    private func catmullRomPath(points: [CGPoint], closed: Bool, alpha: CGFloat = 0.5) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 2 else { return path }

        let count = points.count
        path.move(to: points[0])

        for i in 0..<(closed ? count : count - 1) {
            let p0: CGPoint
            let p1 = points[i]
            let p2 = points[(i + 1) % count]
            let p3: CGPoint

            if closed {
                p0 = points[(i - 1 + count) % count]
                p3 = points[(i + 2) % count]
            } else {
                // Mirror boundary points for open paths to avoid wild tangents
                p0 = i > 0 ? points[i - 1] : CGPoint(x: 2 * p1.x - p2.x, y: 2 * p1.y - p2.y)
                p3 = (i + 2) < count ? points[i + 2] : CGPoint(x: 2 * p2.x - p1.x, y: 2 * p2.y - p1.y)
            }

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )
            path.addCurve(to: p2, controlPoint1: cp1, controlPoint2: cp2)
        }

        if closed { path.close() }
        return path
    }

    private func timingFunction(_ curve: String) -> CAMediaTimingFunction {
        let name: CAMediaTimingFunctionName
        switch curve {
        case "linear":    name = .linear
        case "easeIn":    name = .easeIn
        case "easeInOut": name = .easeInEaseOut
        default:          name = .easeOut
        }
        return CAMediaTimingFunction(name: name)
    }

    /// Map the legacy `animationCurve` string field to `Animation.NamedCurve`.
    /// Unrecognized values fall back to nil so the caller picks its own default.
    private func namedCurve(from string: String?) -> DSL.Model.Animation.NamedCurve? {
        guard let string else { return nil }
        return DSL.Model.Animation.NamedCurve(rawValue: string)
    }
}

// MARK: - StreamingUpdatable

extension CShapeView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CShapeViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)

        // Reset sentinel so new data forces a re-render.
        lastProgress = -1
        applyCurrentProperties(animated: animated)

        propertiesCancellable = vm.properties
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties(animated: true)
            }
        variablesCancellable = vm.variablesChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyCurrentProperties(animated: true)
            }
        return vm
    }
}
