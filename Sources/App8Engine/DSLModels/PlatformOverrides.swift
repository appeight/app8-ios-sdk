import Foundation

extension DSL.Model {

    /// A platform an App8 document can target (app8-dsl `docs/platforms.md`).
    enum Platform: String, Sendable, CaseIterable {
        case ios, android

        /// The platform this engine renders for.
        static let current: Platform = .ios
    }
}

/// Per-node platform overrides (app8-dsl `docs/platforms.md`, "Per-node
/// platform overrides"), applied to raw JSON before Codable decoding so every
/// component type gets them without its own decoder knowing.
///
/// - A node whose `platforms` array does not list the platform does not exist
///   on it: it is dropped from its parent's `children`, an excluded single slot
///   (`template`, `emptyState`, `titleView`, ...) is removed, and an excluded
///   root is reported as `nil`.
/// - The node's `ios` / `android` object is merged over the node (objects merge
///   key by key, arrays and scalars replace); both keys are then dropped.
/// - The same merge is applied to the node's `content`, where overrides are
///   usually written.
///
/// Mirrors the Android engine's `PlatformOverrides`: the same merge, the same
/// depth limit, and the same component slots.
enum PlatformOverrides {

    typealias Object = [String: JSONValue]
    typealias Platform = DSL.Model.Platform

    /// Thrown when a whole document (a screen, a template) does not exist on
    /// this platform. Not a decoding error: callers skip such documents.
    struct Excluded: Error, CustomStringConvertible {
        let id: String?
        let platform: Platform
        var description: String { "'\(id ?? "?")' does not exist on \(platform.rawValue) (platforms)" }
    }

    // MARK: - One node

    /// The node as seen on `platform`, or `nil` when it does not exist there.
    /// Only the node itself and its `content` are merged; see `resolveComponent`
    /// for a whole tree.
    static func apply(_ node: Object, platform: Platform = .current) -> Object? {
        guard isIncluded(node, platform: platform) else { return nil }
        var merged = mergeOwnOverride(node, platform: platform)
        if case .object(let content)? = merged["content"], hasPlatformKey(content) {
            merged["content"] = .object(mergeOwnOverride(content, platform: platform))
        }
        return merged
    }

    /// True unless the node has a `platforms` array without `platform`. A
    /// `platforms` value that is not an array is ignored.
    static func isIncluded(_ node: Object, platform: Platform = .current) -> Bool {
        guard case .array(let list)? = node["platforms"] else { return true }
        return list.contains { if case .string(let s) = $0 { return s == platform.rawValue } else { return false } }
    }

    /// Objects merge recursively, everything else in `override` replaces.
    /// Past `EngineLimits.maxDeepMergeDepth` the base is kept as is.
    static func merge(_ base: Object, _ override: Object, depth: Int = 0) -> Object {
        guard depth < EngineLimits.maxDeepMergeDepth else { return base }
        var out = base
        for (key, value) in override {
            if case .object(let existing)? = out[key], case .object(let incoming) = value {
                out[key] = .object(merge(existing, incoming, depth: depth + 1))
            } else {
                out[key] = value
            }
        }
        return out
    }

    private static func hasPlatformKey(_ object: Object) -> Bool {
        Platform.allCases.contains { object[$0.rawValue] != nil }
    }

    private static func mergeOwnOverride(_ node: Object, platform: Platform) -> Object {
        guard hasPlatformKey(node) else { return node }
        var stripped = node
        for p in Platform.allCases { stripped.removeValue(forKey: p.rawValue) }
        guard case .object(let override)? = node[platform.rawValue] else { return stripped }
        return merge(stripped, override)
    }

    // MARK: - A component tree

    /// Applies overrides to a component node and to every component nested in
    /// its content slots. `nil` when the node itself does not exist on
    /// `platform`. A value that is not an object is returned unchanged (the
    /// decoder reports it as before).
    static func resolveComponent(_ value: JSONValue, platform: Platform = .current, depth: Int = 0) -> JSONValue? {
        guard case .object(let node) = value else { return value }
        // Backstop only: decoding rejects trees this deep anyway.
        guard depth < EngineLimits.maxJSONDepth else { return value }
        guard var resolved = apply(node, platform: platform) else { return nil }
        if case .object(let content)? = resolved["content"] {
            resolved["content"] = .object(resolveSlots(content, platform: platform, depth: depth + 1))
        }
        return .object(resolved)
    }

    /// Single component slots in a component's `content`: an excluded one is removed.
    private static let singleSlots = ["template", "emptyState", "loadingState", "errorState", "defaultSectionHeader", "fallback"]
    /// `[String: Component]` slots: excluded entries are removed (string entries are template references).
    private static let mapSlots = ["templates", "sectionHeaders"]

    private static func resolveSlots(_ content: Object, platform: Platform, depth: Int) -> Object {
        var out = content
        func node(_ v: JSONValue) -> JSONValue? { resolveComponent(v, platform: platform, depth: depth) }

        if case .array(let children)? = out["children"] {
            out["children"] = .array(children.compactMap(node))
        }
        for key in singleSlots {
            guard let v = out[key], case .object = v else { continue }
            out[key] = node(v)
        }
        for key in mapSlots {
            guard case .object(let map)? = out[key] else { continue }
            out[key] = .object(map.compactMapValues(node))
        }
        // navigationBar.titleView
        if case .object(var bar)? = out["navigationBar"], let title = bar["titleView"], case .object = title {
            bar["titleView"] = node(title)
            out["navigationBar"] = .object(bar)
        }
        // bottomBar.component: the bar has nothing to show without it.
        if case .object(var bar)? = out["bottomBar"], let component = bar["component"], case .object = component {
            if let resolved = node(component) {
                bar["component"] = resolved
                out["bottomBar"] = .object(bar)
            } else {
                out["bottomBar"] = nil
            }
        }
        // contextMenu.preview.component: no preview without it.
        if case .object(var menu)? = out["contextMenu"], case .object(var preview)? = menu["preview"],
           let component = preview["component"], case .object = component {
            if let resolved = node(component) {
                preview["component"] = resolved
                menu["preview"] = .object(preview)
            } else {
                menu["preview"] = nil
            }
            out["contextMenu"] = .object(menu)
        }
        // tableView sections[].rows[].children
        if case .array(let sections)? = out["sections"] {
            out["sections"] = .array(sections.map { section in
                guard case .object(var s) = section, case .array(let rows)? = s["rows"] else { return section }
                s["rows"] = .array(rows.map { row in
                    guard case .object(var r) = row, case .array(let children)? = r["children"] else { return row }
                    r["children"] = .array(children.compactMap(node))
                    return .object(r)
                })
                return .object(s)
            })
        }
        return out
    }

    // MARK: - Documents

    private static let markers: [Data] = ["\"ios\"", "\"android\"", "\"platforms\""].map { Data($0.utf8) }

    /// Cheap pre-check: a document with none of the keys needs no pass.
    static func mayHaveOverrides(_ data: Data) -> Bool {
        markers.contains { data.range(of: $0) != nil }
    }

    /// Resolves a component document (a screen) given as JSON. Returns the
    /// data unchanged when it has no overrides or is not valid JSON (the
    /// decoder then reports it as before). Throws `Excluded` when the root
    /// does not exist on `platform`.
    static func resolveDocument(_ data: Data, platform: Platform = .current) throws -> Data {
        guard mayHaveOverrides(data), let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return data }
        return try encode(resolveDocument(json, platform: platform))
    }

    /// `resolveComponent` for a document root: throws `Excluded` instead of returning `nil`.
    static func resolveDocument(_ json: JSONValue, platform: Platform = .current) throws -> JSONValue {
        guard let resolved = resolveComponent(json, platform: platform) else {
            var id: String?
            if case .object(let o) = json, case .string(let s)? = o["id"] { id = s }
            throw Excluded(id: id, platform: platform)
        }
        return resolved
    }

    static func encode(_ json: JSONValue) throws -> Data {
        try JSONEncoder().encode(json)
    }
}
