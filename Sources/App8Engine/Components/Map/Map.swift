import MapKit

/// Thin wrapper around [String: Any] to satisfy Sendable (values are JSON primitives).
struct SendableDict: @unchecked Sendable {
    let values: [String: Any]
    init(_ values: [String: Any]) { self.values = values }
}

// MARK: - Component Definition

extension DSL.Model.Component {

    struct Map {
        typealias C = MapContent
        typealias Entity = ConcreteEntity<C>
    }
}

// MARK: - Properties

extension DSL.Model.Component.Map {

    struct Properties: Decodable, Sendable {
        // Map configuration
        let mapType: MapType?
        let showUserLocation: Bool?
        let zoomEnabled: Bool?
        let scrollEnabled: Bool?
        let rotateEnabled: Bool?
        let pitchEnabled: Bool?

        // Initial region — accepts static object or expression string
        let center: CoordinateValue?
        let span: CoordinateSpan?

        // Annotations (static and dynamic)
        let annotations: [Annotation]?           // Static array
        let annotationsExpression: String?       // "{{properties}}" - dynamic

        // Routing — each accepts static object or expression string
        let showDirections: Bool?
        let routeFrom: CoordinateValue?
        let routeTo: CoordinateValue?
        let routeTransportType: TransportTypeValue?

        // Polyline — an array of coordinates to draw directly (skips MKDirections).
        // Accepts either a static array or an expression resolving to one.
        let polyline: PolylineValue?

        // When true, the polyline coordinates are treated as via-points and each
        // leg is computed via MKDirections so the line follows real roads/paths.
        // When false (default), coords are connected with straight lines.
        let polylineFollowsRoads: Bool?

        // Bindings for user interactions
        let regionBinding: String?               // "{{mapRegion}}"
        let selectedAnnotationBinding: String?   // "{{selectedPin}}"
        let userLocationBinding: String?         // "{{currentUserLocation}}"
        let routeStatusBinding: String?          // "{{routeStatus}}" — written "ok" or "error"

        // Reserved space at each edge of the visible map when auto-fitting to a polyline
        // or to annotations. Use this when sibling UI (e.g. a bottom carousel) sits over
        // the map and would otherwise occlude pins after a fit.
        let viewportInsets: DSL.Model.EdgeInsets?
    }

    /// Decodes from either a static `{ "latitude": X, "longitude": Y }` object
    /// or an expression string like `"{{coordinate}}"`.
    enum CoordinateValue: Decodable, Sendable {
        case coordinate(Coordinate)
        case expression(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let expr = try? container.decode(String.self) {
                self = .expression(expr)
            } else {
                self = .coordinate(try container.decode(Coordinate.self))
            }
        }
    }

    struct Coordinate: Decodable, Sendable {
        let latitude: Double
        let longitude: Double

        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    /// Decodes from either a static array of coordinates `[{ "latitude": X, "longitude": Y }, ...]`
    /// or an expression string like `"{{selectedRouteCoordinates}}"`.
    enum PolylineValue: Decodable, Sendable {
        case coordinates([Coordinate])
        case expression(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let expr = try? container.decode(String.self) {
                self = .expression(expr)
            } else {
                self = .coordinates(try container.decode([Coordinate].self))
            }
        }
    }

    struct CoordinateSpan: Decodable, Sendable {
        let latitudeDelta: Double
        let longitudeDelta: Double

        var mkCoordinateSpan: MKCoordinateSpan {
            MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        }
    }

    struct Annotation: Decodable, Sendable {
        let id: String
        let coordinate: CoordinateValue?         // static object or "{{expr}}"
        let title: String?                       // plain string or "{{expr}}"
        let subtitle: String?                    // plain string or "{{expr}}"
        let image: String?                       // plain string or "{{expr}}"
        let color: String?                       // hex or "{{expr}}"
        let data: [String: AnyCodableValue]?     // Additional data for actions

        /// Raw JSON dict capturing ALL fields (known + custom) for injection as {{item.xxx}} in actions.
        /// @unchecked Sendable because values are JSON primitives (same pattern as AnyCodableValue).
        let rawFields: SendableDict

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            coordinate = try container.decodeIfPresent(CoordinateValue.self, forKey: .coordinate)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            color = try container.decodeIfPresent(String.self, forKey: .color)
            data = try container.decodeIfPresent([String: AnyCodableValue].self, forKey: .data)

            // Capture the full raw dict so any field is available in onAnnotationTap actions
            let rawContainer = try decoder.singleValueContainer()
            let rawDict = try rawContainer.decode([String: AnyCodableValue].self)
            rawFields = SendableDict(rawDict.mapValues { $0.value })
        }

        private enum CodingKeys: String, CodingKey {
            case id, coordinate, title, subtitle, image, color, data
        }
    }

    enum MapType: String, Decodable, Sendable {
        case standard
        case satellite
        case hybrid
        case satelliteFlyover
        case hybridFlyover
        case mutedStandard

        var mkMapType: MKMapType {
            switch self {
            case .standard: return .standard
            case .satellite: return .satellite
            case .hybrid: return .hybrid
            case .satelliteFlyover: return .satelliteFlyover
            case .hybridFlyover: return .hybridFlyover
            case .mutedStandard: return .mutedStandard
            }
        }
    }

    enum TransportType: String, Decodable, Sendable {
        case automobile
        case walking
        case transit

        var mkDirectionsTransportType: MKDirectionsTransportType {
            switch self {
            case .automobile: return .automobile
            case .walking: return .walking
            case .transit: return .transit
            }
        }
    }

    /// Decodes from either a static transport type string ("automobile", "walking", "transit")
    /// or an expression string like `"{{transportMode}}"`.
    enum TransportTypeValue: Decodable, Sendable {
        case transportType(TransportType)
        case expression(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if string.contains("{{") {
                self = .expression(string)
            } else if let type_ = TransportType(rawValue: string) {
                self = .transportType(type_)
            } else {
                self = .transportType(.automobile)
            }
        }
    }
}

// MARK: - Content

struct MapContent: DSL.Model.Component.EntityContent, DSL.Model.StatefulContent, DSL.Model.VariablesHolder, DSL.Model.EventTriggersHolder {
    typealias Properties = DSL.Model.Component.Map.Properties
    typealias Style = DSL.Model.Style.Map
    typealias StateType = DSL.Model.State<Properties, Style>

    let properties: Properties
    var style: Style?
    let layout: DSL.Model.Layout?
    let actions: [DSL.Model.ActionTrigger: DSL.Model.Action]?
    let defaultStateName: String?
    var states: [String: StateType]?
    let triggers: [DSL.Model.Trigger: String]?
    let variables: [String: VariableDefinition]?
    let navigationBar: DSL.Model.NavigationBar?

    // Event triggers
    let onEvent: [DSL.Model.EventTrigger]?

    // Not used for maps
    @SafeArrayDecodable
    var children: [DSL.Model.Component.`Any`] = []

    // MARK: - Decodable

    enum CodingKeys: String, CodingKey {
        case properties, style, layout, actions, defaultStateName, states, triggers, variables, navigationBar, onEvent, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        properties = try c.decode(Properties.self, forKey: .properties)
        style = try c.decodeIfPresent(Style.self, forKey: .style)
        layout = try c.decodeIfPresent(DSL.Model.Layout.self, forKey: .layout)
        navigationBar = try c.decodeIfPresent(DSL.Model.NavigationBar.self, forKey: .navigationBar)

        if let rawActions = try c.decodeIfPresent([String: DSL.Model.Action].self, forKey: .actions) {
            var converted: [DSL.Model.ActionTrigger: DSL.Model.Action] = [:]
            for (key, value) in rawActions {
                if let trigger = DSL.Model.ActionTrigger(rawValue: key) {
                    converted[trigger] = value
                }
            }
            actions = converted.isEmpty ? nil : converted
        } else {
            actions = nil
        }

        defaultStateName = try c.decodeIfPresent(String.self, forKey: .defaultStateName)
        states = try c.decodeIfPresent([String: StateType].self, forKey: .states)
        variables = try c.decodeIfPresent([String: VariableDefinition].self, forKey: .variables)
        onEvent = try c.decodeIfPresent([DSL.Model.EventTrigger].self, forKey: .onEvent)

        if let rawTriggers = try c.decodeIfPresent([String: String].self, forKey: .triggers) {
            var converted: [DSL.Model.Trigger: String] = [:]
            for (key, value) in rawTriggers {
                if let trigger = DSL.Model.Trigger(rawValue: key) {
                    converted[trigger] = value
                }
            }
            triggers = converted.isEmpty ? nil : converted
        } else {
            triggers = nil
        }

        if let children = try c.decodeIfPresent(SafeArrayDecodable<DSL.Model.Component.`Any`>.self, forKey: .children) {
            _children = children
        }
    }

    // MARK: - Style Resolution

    mutating func resolveStateStylePointers(resolver: (String) -> (any DSL.Model.Style.Entity)?) {
        if var statesDict = states {
            for (stateName, var state) in statesDict {
                if var stateStyle = state.style {
                    if !stateStyle.isResolved() {
                        stateStyle.resolveStylePointers(resolver: resolver)
                        state.setResolvedStyle(stateStyle)
                        statesDict[stateName] = state
                    }
                }
            }
            states = statesDict
        }
    }
}
