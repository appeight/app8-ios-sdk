import UIKit
import MapKit
import Combine
// TODO: re-enable CoreLocation when NSLocationWhenInUseUsageDescription is added to Info.plist
// import CoreLocation

@MainActor
final class CMapView: App8BaseView<MapContent>, CViewProtocol, MKMapViewDelegate, UIGestureRecognizerDelegate {

    // MARK: - CViewProtocol

    weak var materialView: MaterialView?
    let contentView = UIView()

    // MARK: - UI

    private lazy var mapView: MKMapView = {
        let map = MKMapView()
        map.delegate = self
        return map
    }()

    // TODO: re-enable when location permission is added
    // private let locationManager = CLLocationManager()

    // MARK: - State

    private var viewModel: CMapViewModel?
    private var cancellables = Set<AnyCancellable>()
    private var currentRouteOverlay: MKOverlay?
    private var annotationsById: [String: CMapAnnotation] = [:]
    private var isUpdatingRegion = false  // prevents feedback loop
    private var isInitialRegionSet = false
    private var tapGesture: UITapGestureRecognizer?

    // MARK: - Setup

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(mapView)
        mapView.cMakeEqualToSuperview()

        mapView.accessibilityIdentifier = "MKMapView"

        // TODO: re-enable when location permission is added
        // locationManager.delegate = self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }

    // Keep the inner MKMapView's interface style aligned with our hierarchy after layout,
    // so subsequent system theme changes don't leave stale tiles. Fires on every iOS
    // version (iOS 17+ trait registration on BaseView is for style re-application, not for
    // MapKit's tile palette).
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        syncMapInterfaceStyle(from: traitCollection)
    }

    // MARK: - Configuration

    func configure(viewModel: CMapViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else {
            return
        }

        bindLayout(
            viewModel.layout,
            in: superview,
            viewRegistry: viewModel.service.componentRegistry.viewRegistry,
            parentComponentPath: viewModel.parentPath,
            keyboardService: viewModel.service.context.keyboardService,
            animated: animated
        )
        bindStyle(viewModel.style, animation: viewModel.animation)

        // Match the surrounding hierarchy's resolved interface style before MapKit's first
        // paint, so initial tile rendering uses the right palette. Without this, MKMapView
        // is created off-window with .unspecified traits (which MapKit treats as light) and
        // visibly flips to dark once the trait cascade finally reaches it.
        syncMapInterfaceStyle(from: superview.traitCollection)

        configureMapProperties()
        setupTapGestureIfNeeded()
        setupBindings()
    }

    private func syncMapInterfaceStyle(from traits: UITraitCollection) {
        let resolved = traits.userInterfaceStyle
        if mapView.overrideUserInterfaceStyle != resolved {
            mapView.overrideUserInterfaceStyle = resolved
        }
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

        if let corner = style?.corner {
            mapView.layer.apply(cornerStyle: corner)
            mapView.clipsToBounds = true
            trackRelativeCorner(corner, on: mapView.layer)
        }
    }

    // MARK: - Map Configuration

    private func configureMapProperties() {
        guard let viewModel = viewModel else { return }
        let props = viewModel.component.properties

        mapView.mapType = props.mapType?.mkMapType ?? .standard

        mapView.isZoomEnabled = props.zoomEnabled ?? true
        mapView.isScrollEnabled = props.scrollEnabled ?? true
        mapView.isRotateEnabled = props.rotateEnabled ?? true
        mapView.isPitchEnabled = props.pitchEnabled ?? true

        // TODO: re-enable user location when NSLocationWhenInUseUsageDescription is added
        // if props.showUserLocation == true {
        //     requestLocationPermissionIfNeeded()
        //     mapView.showsUserLocation = true
        // } else {
        //     mapView.showsUserLocation = false
        // }
        mapView.showsUserLocation = false
    }

    // TODO: re-enable when location permission is added
    // private func requestLocationPermissionIfNeeded() {
    //     let status = locationManager.authorizationStatus
    //     if status == .notDetermined {
    //         locationManager.requestWhenInUseAuthorization()
    //     }
    // }

    // MARK: - Bindings

    private func setupBindings() {
        guard let viewModel = viewModel else { return }

        viewModel.annotations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] annotations in
                self?.updateAnnotations(annotations)
            }
            .store(in: &cancellables)

        viewModel.mapRegion
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] region in
                guard let self = self else { return }

                // Allow initial region setup even while isUpdatingRegion is true —
                // MapKit's default region can fire delegate callbacks before we set ours.
                if !self.isInitialRegionSet {
                    let mapRegion = MKCoordinateRegion(center: region.center, span: region.span)
                    self.mapView.setRegion(mapRegion, animated: false)
                    self.isInitialRegionSet = true
                    return
                }

                guard !self.isUpdatingRegion else { return }

                let mapRegion = MKCoordinateRegion(center: region.center, span: region.span)
                self.mapView.setRegion(mapRegion, animated: true)
            }
            .store(in: &cancellables)

        viewModel.route
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                self?.updateRoute(route)
            }
            .store(in: &cancellables)
    }

    // MARK: - Annotations

    private func updateAnnotations(_ annotations: [CMapViewModel.ResolvedAnnotation]) {
        let existingAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
        mapView.removeAnnotations(existingAnnotations)
        annotationsById.removeAll()

        let mapAnnotations = annotations.map { resolved in
            CMapAnnotation(
                id: resolved.id,
                coordinate: resolved.coordinate,
                title: resolved.title,
                subtitle: resolved.subtitle,
                image: resolved.image,
                color: resolved.color
            )
        }

        for annotation in mapAnnotations {
            annotationsById[annotation.id] = annotation
        }

        mapView.addAnnotations(mapAnnotations)

        // Fit to show all annotations when there's no explicit region.
        if viewModel?.component.properties.center == nil,
           !annotations.isEmpty {
            fitToAnnotations(mapAnnotations)
        }
    }

    private func fitToAnnotations(_ annotations: [MKAnnotation]) {
        guard !annotations.isEmpty else { return }

        let topLeft = MKMapPoint(annotations[0].coordinate)
        var rect = MKMapRect(origin: topLeft, size: MKMapSize(width: 0, height: 0))
        for annotation in annotations.dropFirst() {
            let point = MKMapPoint(annotation.coordinate)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }

        mapView.setVisibleMapRect(rect, edgePadding: resolvedViewportInsets(), animated: true)
    }

    private func resolvedViewportInsets() -> UIEdgeInsets {
        let resolved = viewModel?.component.properties.viewportInsets?
            .resolve(defaultTop: 50, defaultLeft: 50, defaultBottom: 50, defaultRight: 50)
            ?? (top: 50, left: 50, bottom: 50, right: 50)
        return UIEdgeInsets(top: resolved.top, left: resolved.left, bottom: resolved.bottom, right: resolved.right)
    }

    // MARK: - Route

    private func updateRoute(_ route: CMapViewModel.MapRoute?) {
        if let overlay = currentRouteOverlay {
            mapView.removeOverlay(overlay)
            currentRouteOverlay = nil
        }

        if let route = route {
            mapView.addOverlay(route.polyline)
            currentRouteOverlay = route.polyline

            // Fit map to show the route, reserving any DSL-declared viewport insets.
            // Skipped when this is a road-snapped upgrade of an already-fitted preview —
            // bounds are nearly identical and re-fitting would just cause an extra animation.
            if route.shouldFitCamera {
                mapView.setVisibleMapRect(route.polyline.boundingMapRect, edgePadding: resolvedViewportInsets(), animated: true)
            }
        }
    }

    // MARK: - Tap Gesture

    private func setupTapGestureIfNeeded() {
        guard tapGesture == nil, viewModel?.component.actions?[.tap] != nil else { return }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleMapTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        mapView.addGestureRecognizer(tap)
        tapGesture = tap

        // Let built-in double-tap-to-zoom win over our single tap when zoom is enabled.
        for recognizer in mapView.gestureRecognizers ?? [] {
            if let doubleTap = recognizer as? UITapGestureRecognizer, doubleTap !== tap,
               doubleTap.numberOfTapsRequired == 2 {
                tap.require(toFail: doubleTap)
            }
        }
    }

    @objc private func handleMapTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: mapView)
        if let hit = mapView.hitTest(location, with: nil), isAnnotationHit(hit) {
            return  // Let MKMapView's selection path fire onAnnotationTap instead.
        }
        viewModel?.executeAction(for: .tap)
    }

    private func isAnnotationHit(_ view: UIView) -> Bool {
        var current: UIView? = view
        while let v = current, v !== mapView {
            if v is MKAnnotationView { return true }
            current = v.superview
        }
        return false
    }

    // MARK: - UIGestureRecognizerDelegate

    nonisolated func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }

    // MARK: - MKMapViewDelegate

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }

        guard let mapAnnotation = annotation as? CMapAnnotation else {
            return nil
        }

        let identifier = "MapAnnotation"
        let annotationView: MKMarkerAnnotationView

        if let dequeuedView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView {
            annotationView = dequeuedView
            annotationView.annotation = annotation
        } else {
            annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            annotationView.canShowCallout = true
        }

        annotationView.accessibilityIdentifier = "map_pin_\(mapAnnotation.id)"

        if let color = mapAnnotation.color {
            annotationView.markerTintColor = color
        } else {
            annotationView.markerTintColor = .systemRed
        }

        if let imageName = mapAnnotation.image, let image = UIImage(named: imageName) {
            annotationView.glyphImage = image
        } else {
            annotationView.glyphImage = nil
        }

        return annotationView
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation as? CMapAnnotation else { return }
        viewModel?.handleAnnotationTap(annotation.id)
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        viewModel?.handleAnnotationDeselect()
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        // Don't track region changes until our initial region is set, or MapKit's
        // default region would overwrite it.
        guard isInitialRegionSet else { return }

        guard !isUpdatingRegion else { return }
        isUpdatingRegion = true

        let region = mapView.region
        viewModel?.handleRegionChange(region)

        // Reset the flag after a delay so the change can propagate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isUpdatingRegion = false
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)

            if let colorHex = viewModel?.currentStyle?.routeColor {
                renderer.strokeColor = UIColor(withHexString: colorHex)
            } else {
                renderer.strokeColor = .systemBlue
            }

            renderer.lineWidth = viewModel?.currentStyle?.routeWidth ?? 4.0

            return renderer
        }

        return MKOverlayRenderer(overlay: overlay)
    }
}

// TODO: re-enable CLLocationManagerDelegate when location permission is added
// extension CMapView: CLLocationManagerDelegate {
//     nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
//         guard let location = locations.last else { return }
//         Task { @MainActor in
//             viewModel?.handleUserLocationUpdate(location.coordinate)
//         }
//     }
//
//     nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
//         if status == .authorizedWhenInUse || status == .authorizedAlways {
//             Task { @MainActor [weak self] in
//                 self?.locationManager.startUpdatingLocation()
//             }
//         }
//     }
// }
