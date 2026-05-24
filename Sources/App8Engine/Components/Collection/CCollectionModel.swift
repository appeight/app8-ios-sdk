import UIKit

// MARK: - Component Definition

extension DSL.Model.Component {

    struct Collection {
        typealias C = CollectionContent
        typealias Entity = ConcreteEntity<C>
    }
}

// MARK: - Properties

extension DSL.Model.Component.Collection {

    struct SectionDefinition: Decodable, Sendable {
        let key: String
        let data: String              // Expression: "{{settingsItems}}"
        let templateName: String?     // Optional single template reference
        let templateKey: String?      // Optional heterogeneous key path e.g. "item.type"
    }

    struct Properties: Decodable, Sendable {
        // Data source — mutually exclusive; precedence: sectionDefinitions > data
        let data: String?                          // Dynamic: "{{users}}"
        let sectionDefinitions: [SectionDefinition]?  // Multi-source sections, each bound to a different variable

        // Layout
        let layout: Layout?

        // Templates
        let templateName: String?   // Single template reference: "userCard"
        let templateKey: String?    // Heterogeneous: "item.type"

        // Selection
        let selection: Selection?

        // Sections
        let groupBy: String?        // Dynamic grouping of a single data source by expression
        let stickyHeaders: Bool?

        // Clipping
        let clipsToBounds: Bool?        // Controls clipsToBounds on the UICollectionView. Default: true when stickyHeaders, false otherwise.

        // Features
        let pullToRefresh: Bool?
        let pagination: Pagination?
        let inverted: Bool?

        // Section-level layout (for orthogonal scrolling within sections)
        let defaultSectionLayout: Layout?   // Fallback layout applied to all sections
        let sectionLayouts: [String: Layout]?  // Per-section overrides keyed by SectionDefinition.key

        // Scroll tracking
        let scrollOffsetVariable: String?  // Variable name to write scroll offset to

        // Swipe actions (vertical layouts only)
        let swipeActions: SwipeActions?
    }

    // MARK: - Swipe Actions

    struct SwipeActions: Decodable, Sendable {
        let leading: [SwipeAction]?
        let trailing: [SwipeAction]?
        let allowFullSwipe: Bool?  // Default: true — first action triggers on full swipe
    }

    struct SwipeAction: Decodable, Sendable {
        let title: String?
        let systemImage: String?      // SF Symbol name
        let backgroundColor: String?  // Hex color, e.g. "#FF3B30"
        let style: Style?
        let action: DSL.Model.Action?

        enum Style: String, Decodable, Sendable {
            case normal, destructive
        }
    }

    struct Layout: Decodable, Sendable {
        let type: LayoutType?

        // Spacing
        let itemSpacing: CGFloat?
        let lineSpacing: CGFloat?
        let contentInsets: EdgeInsets?

        // Grid specific
        let columns: Int?
        let minItemWidth: CGFloat?
        let rows: Int?

        // Item sizing
        let itemWidth: CGFloat?
        let itemHeight: CGFloat?
        let aspectRatio: CGFloat?
        let estimatedItemHeight: CGFloat?
        /// Estimated width for self-sizing horizontal cells. When set, cells determine their own width.
        let estimatedItemWidth: CGFloat?

        // Scroll behavior
        let separatorStyle: SeparatorStyle?
        let pagingEnabled: Bool?
        let snapToItem: Bool?
        let pagingStyle: PagingStyle?
        let showsScrollIndicator: Bool?
        let scrollEnabled: Bool?

        // Page tracking (for carousels/sliders)
        let currentPageVariable: String?  // Plain variable name (e.g. "currentPage") to update with current page index

        enum LayoutType: String, Decodable, Sendable {
            case vertical, horizontal, grid
        }

        enum SeparatorStyle: String, Decodable, Sendable {
            case none, full, inset
        }

        enum PagingStyle: String, Decodable, Sendable {
            case continuous         // .continuous - smooth scrolling
            case paging             // .groupPaging - snap to leading edge
            case pagingCentered     // .groupPagingCentered - snap to center
        }
    }

    struct Selection: Decodable, Sendable {
        let mode: SelectionMode?
        let binding: String?         // "{{selectedIds}}"

        enum SelectionMode: String, Decodable, Sendable {
            case none, single, multiple
        }
    }

    struct Pagination: Decodable, Sendable {
        let enabled: Bool?
        let threshold: Int?
    }

    struct EdgeInsets: Decodable, Sendable {
        let top: CGFloat?
        let left: CGFloat?
        let bottom: CGFloat?
        let right: CGFloat?

        var nsDirectionalEdgeInsets: NSDirectionalEdgeInsets {
            NSDirectionalEdgeInsets(
                top: top ?? 0,
                leading: left ?? 0,
                bottom: bottom ?? 0,
                trailing: right ?? 0
            )
        }
    }
}

// MARK: - Template Reference

extension DSL.Model.Component.Collection {

    /// Template can be either a string reference or an inline component
    enum TemplateRef: Decodable, Sendable {
        case reference(String)
        case inline(DSL.Model.Component.`Any`)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let ref = try? container.decode(String.self) {
                self = .reference(ref)
            } else {
                self = .inline(try container.decode(DSL.Model.Component.`Any`.self))
            }
        }
    }
}

// MARK: - Content

struct CollectionContent: DSL.Model.Component.EntityContent, DSL.Model.StatefulContent, DSL.Model.VariablesHolder, DSL.Model.EventTriggersHolder {
    typealias Properties = DSL.Model.Component.Collection.Properties
    typealias Style = DSL.Model.Style.Collection
    typealias StateType = DSL.Model.State<Properties, Style>

    let properties: Properties
    var style: Style?
    let layout: DSL.Model.Layout?
    let actions: [DSL.Model.ActionTrigger: [DSL.Model.Action]]?
    let analytics: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding]?
    let defaultStateName: String?
    var states: [String: StateType]?
    let triggers: [DSL.Model.Trigger: String]?
    let variables: [String: VariableDefinition]?
    let navigationBar: DSL.Model.NavigationBar?

    // Event triggers
    let onEvent: [DSL.Model.EventTrigger]?

    // Template definitions (inline or referenced)
    var template: DSL.Model.Component.`Any`?
    var templates: [String: DSL.Model.Component.Collection.TemplateRef]?

    // State views
    var emptyState: DSL.Model.Component.`Any`?
    var loadingState: DSL.Model.Component.`Any`?
    var errorState: DSL.Model.Component.`Any`?

    // Section header
    var defaultSectionHeader: DSL.Model.Component.`Any`?
    var sectionHeaders: [String: DSL.Model.Component.`Any`]?

    // Not used for collection (items come from data/templates)
    @SafeArrayDecodable
    var children: [DSL.Model.Component.`Any`] = []

    // MARK: - Decodable

    enum CodingKeys: String, CodingKey {
        case properties, style, layout, actions, analytics, defaultStateName, states, triggers, variables, navigationBar, onEvent
        case template, templates, emptyState, loadingState, errorState, defaultSectionHeader, sectionHeaders, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        properties = try c.decode(Properties.self, forKey: .properties)
        style = try c.decodeIfPresent(Style.self, forKey: .style)
        layout = try c.decodeIfPresent(DSL.Model.Layout.self, forKey: .layout)
        navigationBar = try c.decodeIfPresent(DSL.Model.NavigationBar.self, forKey: .navigationBar)

        if let rawAnalytics = try c.decodeIfPresent([String: DSL.Model.AnalyticsBinding].self, forKey: .analytics) {
            var converted: [DSL.Model.ActionTrigger: DSL.Model.AnalyticsBinding] = [:]
            for (key, value) in rawAnalytics {
                if let trigger = DSL.Model.ActionTrigger(rawValue: key) {
                    converted[trigger] = value
                }
            }
            analytics = converted.isEmpty ? nil : converted
        } else {
            analytics = nil
        }

        if let rawActions = try c.decodeIfPresent([String: DSL.Model.ActionList].self, forKey: .actions) {
            var converted: [DSL.Model.ActionTrigger: [DSL.Model.Action]] = [:]
            for (key, value) in rawActions {
                if let trigger = DSL.Model.ActionTrigger(rawValue: key) {
                    converted[trigger] = value.actions
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

        // Collection-specific
        template = try c.decodeIfPresent(DSL.Model.Component.`Any`.self, forKey: .template)
        templates = try c.decodeIfPresent([String: DSL.Model.Component.Collection.TemplateRef].self, forKey: .templates)
        emptyState = try c.decodeIfPresent(DSL.Model.Component.`Any`.self, forKey: .emptyState)
        loadingState = try c.decodeIfPresent(DSL.Model.Component.`Any`.self, forKey: .loadingState)
        errorState = try c.decodeIfPresent(DSL.Model.Component.`Any`.self, forKey: .errorState)
        defaultSectionHeader = try c.decodeIfPresent(DSL.Model.Component.`Any`.self, forKey: .defaultSectionHeader)
        sectionHeaders = try c.decodeIfPresent([String: DSL.Model.Component.`Any`].self, forKey: .sectionHeaders)

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

        // Resolve inline template styles
        if var tmpl = template {
            tmpl.resolveStylePointers(resolver: resolver)
            template = tmpl
        }

        // Resolve heterogeneous templates
        if var tmpls = templates {
            for (key, ref) in tmpls {
                if case .inline(var component) = ref {
                    component.resolveStylePointers(resolver: resolver)
                    tmpls[key] = .inline(component)
                }
            }
            templates = tmpls
        }

        // Resolve state views
        if var empty = emptyState {
            empty.resolveStylePointers(resolver: resolver)
            emptyState = empty
        }
        if var loading = loadingState {
            loading.resolveStylePointers(resolver: resolver)
            loadingState = loading
        }
        if var error = errorState {
            error.resolveStylePointers(resolver: resolver)
            errorState = error
        }

        // Resolve section header
        if var header = defaultSectionHeader {
            header.resolveStylePointers(resolver: resolver)
            defaultSectionHeader = header
        }

        // Resolve per-section headers
        if var headers = sectionHeaders {
            for (key, var header) in headers {
                header.resolveStylePointers(resolver: resolver)
                headers[key] = header
            }
            sectionHeaders = headers
        }
    }
}
