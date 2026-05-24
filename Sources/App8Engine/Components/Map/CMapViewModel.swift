import MapKit
import Combine

@MainActor
final class CMapViewModel: CBaseViewModel<MapContent> {

    // MARK: - Types

    struct ResolvedAnnotation: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String?
        let subtitle: String?
        let image: String?
        let color: UIColor?
        let data: [String: AnyCodableValue]?
        let rawFields: SendableDict
    }

    struct MapRegion {
        let center: CLLocationCoordinate2D
        let span: MKCoordinateSpan
    }

    struct MapRoute {
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        let polyline: MKPolyline
        let distance: CLLocationDistance
        let expectedTravelTime: TimeInterval
        /// When false, the view should swap the overlay without re-fitting the camera —
        /// used for the road-snapped upgrade after the optimistic straight-line emit.
        let shouldFitCamera: Bool
    }

    // MARK: - Published State

    private let annotationsSubject = CurrentValueSubject<[ResolvedAnnotation], Never>([])
    var annotations: AnyPublisher<[ResolvedAnnotation], Never> {
        annotationsSubject.eraseToAnyPublisher()
    }

    var currentAnnotations: [ResolvedAnnotation] {
        annotationsSubject.value
    }

    private let mapRegionSubject = CurrentValueSubject<MapRegion?, Never>(nil)
    var mapRegion: AnyPublisher<MapRegion?, Never> {
        mapRegionSubject.eraseToAnyPublisher()
    }

    private let routeSubject = CurrentValueSubject<MapRoute?, Never>(nil)
    var route: AnyPublisher<MapRoute?, Never> {
        routeSubject.eraseToAnyPublisher()
    }

    private let userLocationSubject = CurrentValueSubject<CLLocationCoordinate2D?, Never>(nil)
    var userLocation: AnyPublisher<CLLocationCoordinate2D?, Never> {
        userLocationSubject.eraseToAnyPublisher()
    }

    // MARK: - Private State

    private var annotationsSubscription: AnyCancellable?
    private var routeCalculationTask: Task<Void, Never>?
    private var polylineCalculationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    override func setup() {
        super.setup()
        observeAnnotations()
        observePolyline()
        observeRoute()
        setupInitialRegion()
    }

    // MARK: - Initial Region

    private func setupInitialRegion() {
        let center = component.properties.center.flatMap(resolveCoordinateValue)
        let span = component.properties.span?.mkCoordinateSpan ?? MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)

        if let center = center {
            mapRegionSubject.send(MapRegion(center: center, span: span))
        }
    }

    // MARK: - Annotations

    private func observeAnnotations() {
        if let annotationsExpression = component.properties.annotationsExpression {
            refreshAnnotations()

            annotationsSubscription = variableStore.anyVariableChanged
                .sink { [weak self] variableName in
                    guard let self = self else { return }
                    if self.expressionMightDependOn(annotationsExpression, variableName: variableName) {
                        self.refreshAnnotations()
                    }
                }
        } else if let staticAnnotations = component.properties.annotations {
            // Static annotations: resolve once, plus re-resolve on any variable change
            // when at least one field carries a {{...}} expression.
            refreshStaticAnnotations(staticAnnotations)

            if staticAnnotations.contains(where: annotationContainsExpression) {
                annotationsSubscription = variableStore.anyVariableChanged
                    .sink { [weak self] _ in
                        guard let self = self else { return }
                        self.refreshStaticAnnotations(staticAnnotations)
                    }
            }
        } else {
            annotationsSubject.send([])
        }
    }

    private func refreshStaticAnnotations(_ annotations: [DSL.Model.Component.Map.Annotation]) {
        let resolved = annotations.compactMap { resolveAnnotation($0) }
        annotationsSubject.send(resolved)
    }

    private func annotationContainsExpression(_ annotation: DSL.Model.Component.Map.Annotation) -> Bool {
        if case .expression = annotation.coordinate { return true }
        if annotation.title?.contains("{{") == true { return true }
        if annotation.subtitle?.contains("{{") == true { return true }
        if annotation.image?.contains("{{") == true { return true }
        if annotation.color?.contains("{{") == true { return true }
        return false
    }

    private func refreshAnnotations() {
        guard let annotationsExpression = component.properties.annotationsExpression else { return }

        let resolved = resolveProperty(annotationsExpression)

        if let array = resolved as? [Any] {
            let annotations = array.enumerated().compactMap { index, item -> ResolvedAnnotation? in
                resolveAnnotationFromValue(item, index: index)
            }
            annotationsSubject.send(annotations)
        } else {
            annotationsSubject.send([])
        }
    }

    private func resolveAnnotation(_ annotation: DSL.Model.Component.Map.Annotation) -> ResolvedAnnotation? {
        guard let coordValue = annotation.coordinate,
              let coordinate = resolveCoordinateValue(coordValue) else { return nil }

        let title    = annotation.title.flatMap { resolveProperty($0) as? String }
        let subtitle = annotation.subtitle.flatMap { resolveProperty($0) as? String }
        let image    = annotation.image.flatMap { resolveProperty($0) as? String }
        let color    = annotation.color
            .flatMap { resolveProperty($0) as? String }
            .flatMap { UIColor(withHexString: $0) }

        return ResolvedAnnotation(
            id: annotation.id,
            coordinate: coordinate,
            title: title,
            subtitle: subtitle,
            image: image,
            color: color,
            data: annotation.data,
            rawFields: annotation.rawFields
        )
    }

    private func resolveAnnotationFromValue(_ value: Any, index: Int) -> ResolvedAnnotation? {
        guard let dict = value as? [String: Any] else { return nil }

        let coordinate: CLLocationCoordinate2D?
        if let coordinateDict = dict["coordinate"] as? [String: Any],
           let lat = coordinateDict["latitude"] as? Double,
           let lng = coordinateDict["longitude"] as? Double {
            // Support: { coordinate: { latitude: X, longitude: Y } }
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let location = dict["location"] as? [String: Any],
                  let lat = location["latitude"] as? Double,
                  let lng = location["longitude"] as? Double {
            // Support: { location: { latitude: X, longitude: Y } }
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let lat = dict["latitude"] as? Double,
                  let lng = dict["longitude"] as? Double {
            // Support: { latitude: X, longitude: Y }
            coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            return nil
        }

        guard let coordinate = coordinate else { return nil }

        let id = (dict["id"] as? String) ?? "\(index)"
        let title = dict["title"] as? String ?? dict["name"] as? String
        let subtitle = dict["subtitle"] as? String ?? dict["address"] as? String ?? dict["description"] as? String
        let image = dict["image"] as? String ?? dict["icon"] as? String
        let color: UIColor? = {
            if let colorString = dict["color"] as? String {
                return UIColor(withHexString: colorString)
            }
            return nil
        }()

        let data = dict.mapValues { AnyCodableValue(value: $0) }

        return ResolvedAnnotation(
            id: id,
            coordinate: coordinate,
            title: title,
            subtitle: subtitle,
            image: image,
            color: color,
            data: data,
            rawFields: SendableDict(dict)
        )
    }

    // MARK: - Route

    private func observeRoute() {
        // Polyline takes precedence — when a direct polyline is provided,
        // we skip MKDirections entirely.
        guard component.properties.polyline == nil else { return }
        guard component.properties.showDirections == true else { return }

        calculateRouteIfNeeded()

        let hasExpressionDependency: Bool = {
            if case .expression = component.properties.routeFrom { return true }
            if case .expression = component.properties.routeTo { return true }
            if case .expression = component.properties.routeTransportType { return true }
            return false
        }()
        if hasExpressionDependency {
            variableStore.anyVariableChanged
                .sink { [weak self] variableName in
                    guard let self else { return }
                    if self.routeExpressionMightDependOn(variableName: variableName) {
                        self.calculateRouteIfNeeded()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func calculateRouteIfNeeded() {
        let from = component.properties.routeFrom.flatMap(resolveCoordinateValue)
        let to = component.properties.routeTo.flatMap(resolveCoordinateValue)

        guard let from = from, let to = to else {
            routeSubject.send(nil)
            return
        }

        // Clear status immediately so any previous error message hides before the result arrives
        if let binding = component.properties.routeStatusBinding {
            updateVariableFromBinding(binding, value: "")
        }

        calculateRoute(from: from, to: to)
    }

    private func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) {
        routeCalculationTask?.cancel()

        routeCalculationTask = Task {
            do {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
                request.transportType = resolveTransportType() ?? .automobile

                let directions = MKDirections(request: request)
                let response = try await directions.calculate()

                guard !Task.isCancelled, let route = response.routes.first else { return }

                let mapRoute = MapRoute(
                    from: from,
                    to: to,
                    polyline: route.polyline,
                    distance: route.distance,
                    expectedTravelTime: route.expectedTravelTime,
                    shouldFitCamera: true
                )

                await MainActor.run {
                    routeSubject.send(mapRoute)
                    if let binding = component.properties.routeStatusBinding {
                        updateVariableFromBinding(binding, value: "ok")
                    }
                }
            } catch {
                service.context.logger.error("Failed to calculate route: \(error)")
                await MainActor.run {
                    routeSubject.send(nil)
                    if let binding = component.properties.routeStatusBinding {
                        updateVariableFromBinding(binding, value: "error")
                    }
                }
            }
        }
    }

    // MARK: - Polyline

    private func observePolyline() {
        guard let polylineValue = component.properties.polyline else { return }

        buildPolyline()

        if case .expression = polylineValue {
            variableStore.anyVariableChanged
                .sink { [weak self] variableName in
                    guard let self else { return }
                    if self.polylineExpressionMightDependOn(variableName: variableName) {
                        self.buildPolyline()
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func buildPolyline() {
        guard let polylineValue = component.properties.polyline else { return }

        let coords = resolvePolylineCoordinates(polylineValue)

        guard coords.count >= 2 else {
            polylineCalculationTask?.cancel()
            routeSubject.send(nil)
            return
        }

        if component.properties.polylineFollowsRoads == true {
            // Show via-points connected by straight lines immediately so the camera
            // can settle on the new route without waiting for MKDirections.
            let preview = MKPolyline(coordinates: coords, count: coords.count)
            emitPolyline(preview, from: coords.first!, to: coords.last!, shouldFitCamera: true)
            // Then upgrade to a road-snapped polyline in the background.
            buildRoadFollowingPolyline(coords: coords)
        } else {
            polylineCalculationTask?.cancel()
            let polyline = MKPolyline(coordinates: coords, count: coords.count)
            emitPolyline(polyline, from: coords.first!, to: coords.last!, shouldFitCamera: true)
        }
    }

    private func buildRoadFollowingPolyline(coords: [CLLocationCoordinate2D]) {
        polylineCalculationTask?.cancel()

        let transport = resolveTransportType() ?? .walking

        polylineCalculationTask = Task { [weak self] in
            // Fetch every leg in parallel — wall-clock latency drops from
            // "sum of all legs" to "the slowest leg".
            let legs: [[CLLocationCoordinate2D]] = await withTaskGroup(
                of: (Int, [CLLocationCoordinate2D]).self
            ) { group in
                for i in 0..<(coords.count - 1) {
                    group.addTask {
                        let leg = await MKDirectionsLegCache.fetch(
                            from: coords[i],
                            to: coords[i + 1],
                            transport: transport
                        )
                        return (i, leg)
                    }
                }
                var collected: [(Int, [CLLocationCoordinate2D])] = []
                collected.reserveCapacity(coords.count - 1)
                for await item in group { collected.append(item) }
                return collected.sorted { $0.0 < $1.0 }.map { $0.1 }
            }

            if Task.isCancelled { return }

            var allPoints: [CLLocationCoordinate2D] = []
            allPoints.reserveCapacity(coords.count * 8)
            for leg in legs {
                // Avoid doubling the join point between consecutive legs.
                if !allPoints.isEmpty, let first = leg.first,
                   let last = allPoints.last,
                   abs(first.latitude - last.latitude) < 1e-6,
                   abs(first.longitude - last.longitude) < 1e-6 {
                    allPoints.append(contentsOf: leg.dropFirst())
                } else {
                    allPoints.append(contentsOf: leg)
                }
            }

            guard !Task.isCancelled, allPoints.count >= 2 else { return }

            let polyline = MKPolyline(coordinates: allPoints, count: allPoints.count)

            await MainActor.run {
                guard let self else { return }
                // Road-snapped upgrade — swap the overlay but don't re-fit; the camera
                // already settled on the straight-line preview and the bounds are nearly
                // identical, so re-fitting would only cause a redundant animation.
                self.emitPolyline(polyline, from: coords.first!, to: coords.last!, shouldFitCamera: false)
            }
        }
    }

    private func emitPolyline(
        _ polyline: MKPolyline,
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        shouldFitCamera: Bool
    ) {
        let mapRoute = MapRoute(
            from: from,
            to: to,
            polyline: polyline,
            distance: 0,
            expectedTravelTime: 0,
            shouldFitCamera: shouldFitCamera
        )
        routeSubject.send(mapRoute)
    }

    private func resolvePolylineCoordinates(_ value: DSL.Model.Component.Map.PolylineValue) -> [CLLocationCoordinate2D] {
        switch value {
        case .coordinates(let coords):
            return coords.map { $0.clCoordinate }
        case .expression(let expr):
            let resolved = resolveProperty(expr)
            guard let array = resolved as? [Any] else { return [] }
            return array.compactMap { item -> CLLocationCoordinate2D? in
                if let dict = item as? [String: Any],
                   let lat = dict["latitude"] as? Double,
                   let lng = dict["longitude"] as? Double {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
                if let dict = item as? [String: Double],
                   let lat = dict["latitude"],
                   let lng = dict["longitude"] {
                    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                }
                return nil
            }
        }
    }

    private func polylineExpressionMightDependOn(variableName: String) -> Bool {
        if case .expression(let expr) = component.properties.polyline,
           expressionMightDependOn(expr, variableName: variableName) { return true }
        return false
    }

    // MARK: - User Interactions

    func handleAnnotationTap(_ annotationId: String) {
        guard let annotation = annotationsSubject.value.first(where: { $0.id == annotationId }) else { return }

        if let binding = component.properties.selectedAnnotationBinding {
            updateVariableFromBinding(binding, value: annotationId)
        }

        if let actions = component.actions?[.onAnnotationTap] {
            // Create scoped store with annotation data accessible as {{item.xxx}}.
            // rawFields contains every JSON field from the annotation (id, title, subtitle,
            // coordinate, color, plus any custom fields the DSL author added).
            let actionStore = ScopedVariableStore(parent: variableStore)

            do {
                try actionStore.defineVariable(
                    name: "item",
                    definition: VariableDefinition(type: .object, initialValue: annotation.rawFields.values)
                )
            } catch {
                service.context.logger.error("Failed to define annotation action variables: \(error)")
            }

            let handler = VariableActionHandler()
            for action in actions {
                do {
                    try handler.execute(action: action, store: actionStore, context: VariableContext(store: actionStore))
                } catch {
                    service.context.logger.error("Failed to execute onAnnotationTap action: \(error)")
                }
            }
        }
    }

    func handleAnnotationDeselect() {
        if let binding = component.properties.selectedAnnotationBinding {
            updateVariableFromBinding(binding, value: "")
        }
    }

    func handleRegionChange(_ region: MKCoordinateRegion) {
        let mapRegion = MapRegion(center: region.center, span: region.span)
        mapRegionSubject.send(mapRegion)

        if let binding = component.properties.regionBinding {
            let regionDict: [String: Any] = [
                "center": [
                    "latitude": region.center.latitude,
                    "longitude": region.center.longitude
                ],
                "span": [
                    "latitudeDelta": region.span.latitudeDelta,
                    "longitudeDelta": region.span.longitudeDelta
                ]
            ]
            updateVariableFromBinding(binding, value: regionDict)
        }

        if let actions = component.actions?[.onRegionChange] {
            for action in actions { executeAction(action) }
        }
    }

    func handleUserLocationUpdate(_ location: CLLocationCoordinate2D) {
        userLocationSubject.send(location)

        if let binding = component.properties.userLocationBinding {
            let locationDict: [String: Double] = [
                "latitude": location.latitude,
                "longitude": location.longitude
            ]
            updateVariableFromBinding(binding, value: locationDict)
        }

        if let actions = component.actions?[.onUserLocationUpdate] {
            for action in actions { executeAction(action) }
        }
    }

    // MARK: - Helpers

    private func routeExpressionMightDependOn(variableName: String) -> Bool {
        if case .expression(let expr) = component.properties.routeFrom,
           expressionMightDependOn(expr, variableName: variableName) { return true }
        if case .expression(let expr) = component.properties.routeTo,
           expressionMightDependOn(expr, variableName: variableName) { return true }
        if case .expression(let expr) = component.properties.routeTransportType,
           expressionMightDependOn(expr, variableName: variableName) { return true }
        return false
    }

    private func resolveTransportType() -> MKDirectionsTransportType? {
        guard let value = component.properties.routeTransportType else { return nil }
        switch value {
        case .transportType(let type_):
            return type_.mkDirectionsTransportType
        case .expression(let expr):
            guard let string = resolveProperty(expr) as? String,
                  let type_ = DSL.Model.Component.Map.TransportType(rawValue: string) else { return nil }
            return type_.mkDirectionsTransportType
        }
    }

    private func resolveCoordinateValue(_ value: DSL.Model.Component.Map.CoordinateValue) -> CLLocationCoordinate2D? {
        switch value {
        case .coordinate(let coord): return coord.clCoordinate
        case .expression(let expr): return resolveCoordinate(from: expr)
        }
    }

    private func resolveCoordinate(from expression: String) -> CLLocationCoordinate2D? {
        let resolved = resolveProperty(expression)

        if let dict = resolved as? [String: Any],
           let lat = dict["latitude"] as? Double,
           let lng = dict["longitude"] as? Double {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else if let dict = resolved as? [String: Double],
                  let lat = dict["latitude"],
                  let lng = dict["longitude"] {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }

        return nil
    }

    private func expressionMightDependOn(_ expression: String, variableName: String) -> Bool {
        return expression.contains(variableName)
    }

    private func updateVariableFromBinding(_ binding: String, value: Any) {
        // binding is like "{{selectedPin}}"; extract the variable name.
        let variableName = binding
            .replacingOccurrences(of: "{{", with: "")
            .replacingOccurrences(of: "}}", with: "")
            .trimmingCharacters(in: .whitespaces)

        do {
            try variableStore.setValue(name: variableName, value: value)
        } catch {
            service.context.logger.error("Failed to update variable '\(variableName)': \(error)")
        }
    }
}

// MARK: - MKPolyline coordinate extraction

extension MKPolyline {
    /// Returns every coordinate point in the polyline as CLLocationCoordinate2D.
    /// Used to stitch MKDirections leg polylines into one combined polyline.
    var coordinatesArray: [CLLocationCoordinate2D] {
        var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

// MARK: - Process-wide leg cache for MKDirections

/// In-memory cache of MKDirections results, keyed by (from, to, transport).
///
/// Two wins over per-instance caches:
///  • A leg computed by one CMapView (e.g. main map) is immediately usable by
///    any other CMapView (e.g. modal route preview) without a second request.
///  • Concurrent callers for the same leg share a single in-flight Task instead
///    of each firing their own request — which matters a lot at app-open when
///    two maps with the same polyline come up at once.
///
/// Only successfully-routed legs are cached (>2 points). Straight-line fallbacks
/// from failures aren't cached, so the next call retries after rate limits clear.
@MainActor
private enum MKDirectionsLegCache {
    private static var successful: [String: [CLLocationCoordinate2D]] = [:]
    private static var inflight: [String: Task<[CLLocationCoordinate2D], Never>] = [:]

    static func fetch(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType
    ) async -> [CLLocationCoordinate2D] {
        let cacheKey = key(from: from, to: to, transport: transport)

        if let cached = successful[cacheKey] { return cached }
        if let existing = inflight[cacheKey] { return await existing.value }

        let task = Task<[CLLocationCoordinate2D], Never> {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = transport
            do {
                let response = try await MKDirections(request: request).calculate()
                return response.routes.first?.polyline.coordinatesArray ?? [from, to]
            } catch {
                return [from, to]
            }
        }
        inflight[cacheKey] = task
        let result = await task.value
        // count > 2 implies MKDirections returned a real route, not just [from, to].
        if result.count > 2 {
            successful[cacheKey] = result
        }
        inflight.removeValue(forKey: cacheKey)
        return result
    }

    private static func key(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType
    ) -> String {
        String(
            format: "%.5f,%.5f|%.5f,%.5f|%d",
            from.latitude, from.longitude,
            to.latitude, to.longitude,
            transport.rawValue
        )
    }
}
