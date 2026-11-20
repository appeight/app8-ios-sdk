//
//  RobustnessFuzzTests.swift
//  App8EngineTests
//
//  The engine must never crash on JSON it cannot fully handle: it skips or
//  blanks the part it cannot render and logs a warning. This test starts real
//  apps (App8.startApp in a window) from a corpus of DSL bundles, unmutated
//  and with seeded random mutations: dropped keys, wrong value types, unknown
//  component / action / enum values, empty arrays, out-of-range numbers and
//  broken expressions. It passes when the process survives; a crash names the
//  case and seed on stderr (`fuzz: <case> seed <n>`) right before it ran.
//
//  Corpus:
//  - built in: every JSON example in docs/dsl that decodes as a component,
//    wrapped in a screen, plus a few hand-written bundles that cover
//    templates by name, section templates, pagers and tab bars;
//  - APP8_FUZZ_FIXTURES (colon-separated directories, optional): every case
//    under <root>/{apps,screens,components,...} in the conformance layout
//    (app.json + screens/ + styles/ + templates/ + datasources/, or
//    screen.json, or component.json). Under xcodebuild pass it as
//    TEST_RUNNER_APP8_FUZZ_FIXTURES.
//  - APP8_FUZZ_ROUNDS: mutated variants per case (default 3),
//    APP8_FUZZ_SEED: base seed (default 1120), APP8_FUZZ_SHARD: "i/n" runs
//    every n-th case from i, APP8_FUZZ_START=<case id> resumes from a case.
//

import XCTest
import UIKit
@testable import App8Engine

// MARK: - Bundle

/// One DSL bundle as JSON trees (JSONSerialization output).
private struct FuzzBundle {
    var app: Any
    var styles: [Any]
    var templates: [Any]
    var screens: [String: Any]
    var datasources: [String: Any]
    var startScreen: String

    static func synthApp(start: String) -> [String: Any] {
        ["title": "fuzz",
         "navigation": ["startFlow": "main-flow",
                        "flows": [["id": "main-flow", "startScreen": start]]]]
    }

    /// The same bundle, starting at `screen` (every screen of an app gets a turn).
    func starting(at screen: String) -> FuzzBundle {
        var copy = self
        copy.startScreen = screen
        if var app = app as? [String: Any], var nav = app["navigation"] as? [String: Any] {
            let start = nav["startFlow"] as? String ?? "main-flow"
            var flows = nav["flows"] as? [[String: Any]] ?? []
            if let i = flows.firstIndex(where: { $0["id"] as? String == start }) {
                flows[i]["startScreen"] = screen
            } else {
                flows.append(["id": start, "startScreen": screen])
            }
            nav["flows"] = flows
            app["navigation"] = nav
            copy.app = app
        } else {
            copy.app = Self.synthApp(start: screen)
        }
        return copy
    }
}

private final class FuzzDataSource: App8DataSource, @unchecked Sendable {
    let app: Data, styles: [Data], templates: [Data]
    let screens: [String: Data], datasources: [String: Data]

    init(_ b: FuzzBundle) {
        func d(_ v: Any) -> Data {
            (try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed])) ?? Data("null".utf8)
        }
        app = d(b.app)
        styles = b.styles.map(d)
        templates = b.templates.map(d)
        screens = b.screens.mapValues(d)
        datasources = b.datasources.mapValues(d)
    }
    func getApp() async throws -> Data { app }
    func getStyles() async throws -> [Data] { styles }
    func getComponents() async throws -> [Data] { templates }
    func getComponent(componentId: String) async throws -> Data { throw URLError(.fileDoesNotExist) }
    func getScreen(screenId: String) async throws -> Data {
        guard let s = screens[screenId] else { throw URLError(.fileDoesNotExist) }
        return s
    }
    func getDatasource(screenId: String, datasourceId: String) async throws -> Data {
        guard let d = datasources[datasourceId] else { throw URLError(.fileDoesNotExist) }
        return d
    }
    func getAsset(assetId: String?, assetName: String?) async throws -> Data? { nil }
    func getAllScreenIds() async throws -> [String]? { Array(screens.keys) }
    func streamScreen(screenId: String) -> AsyncStream<Data>? { nil }
    func streamDatasource(screenId: String, datasourceId: String, componentPath: String?) -> AsyncStream<Data>? { nil }
    func streamStyles() -> AsyncStream<Data>? { nil }
}

// MARK: - Mutator

/// SplitMix64: small, seedable, the same sequence on every run.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private struct Mutator {
    var rng: SeededRandom
    /// Chance that a node is mutated.
    let rate: Double

    private static let unknownTypes = ["hologram", "futureWidget", "carousel3D", "", "VIEW"]
    private static let oddStrings = ["", "bogus-value", "{{ broken ( ", "{{ items[99].title }}",
                                     "{{ 1 / 0 }}", "{{ undefinedVar.deep.path }}", "#zzzzzz",
                                     "-1", "NaN", "1e309", "missing-template", "missing-font-xyz"]
    private static let oddNumbers: [Double] = [-1, 0, 99_999_999, -99_999_999, 0.000001, 1e300, 3.5]

    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &rng) < p }

    mutating func wrongValue() -> Any {
        switch Int.random(in: 0..<9, using: &rng) {
        case 0: return Self.oddStrings.randomElement(using: &rng)!
        case 1: return Self.oddNumbers.randomElement(using: &rng)!
        case 2: return Bool.random(using: &rng)
        case 3: return NSNull()
        case 4: return [Any]()
        case 5: return [String: Any]()
        case 6: return ["type": Self.unknownTypes.randomElement(using: &rng)!, "content": [String: Any]()]
        case 7: return [NSNull(), "x", 1] as [Any]
        default: return "{{ " + (Self.oddStrings.randomElement(using: &rng)!) + " }}"
        }
    }

    mutating func mutate(_ value: Any, depth: Int = 0) -> Any {
        guard depth < 64 else { return value }
        switch value {
        case var dict as [String: Any]:
            for key in dict.keys.sorted() {
                guard let child = dict[key] else { continue }
                if chance(rate) {
                    switch Int.random(in: 0..<5, using: &rng) {
                    case 0: dict[key] = nil                                   // dropped key
                    case 1 where key == "type":                               // unknown component / action / style type
                        dict[key] = Self.unknownTypes.randomElement(using: &rng)!
                    case 2 where child is String:                             // unknown enum value / bad expression
                        dict[key] = Self.oddStrings.randomElement(using: &rng)!
                    case 3 where child is NSNumber:                           // out-of-range numbers / indexes
                        dict[key] = Self.oddNumbers.randomElement(using: &rng)!
                    default: dict[key] = wrongValue()                         // wrong type
                    }
                } else {
                    dict[key] = mutate(child, depth: depth + 1)
                }
            }
            if chance(rate / 4) { dict["unknownProperty\(Int.random(in: 0..<9, using: &rng))"] = wrongValue() }
            return dict
        case var array as [Any]:
            if chance(rate) {
                switch Int.random(in: 0..<4, using: &rng) {
                case 0: return [Any]()                                        // empty array
                case 1: array.append(NSNull())                                // null item
                case 2 where !array.isEmpty: array.append(array[0])           // duplicate (same ids)
                default: array.append(["type": Self.unknownTypes.randomElement(using: &rng)!,
                                       "id": "fuzz-unknown", "content": ["layout": [:] as [String: Any]]])
                }
            }
            return array.map { mutate($0, depth: depth + 1) }
        default:
            return value
        }
    }

    mutating func mutate(_ b: FuzzBundle) -> FuzzBundle {
        var out = b
        out.screens = b.screens.mapValues { mutate($0) }
        out.templates = b.templates.map { mutate($0) }
        out.datasources = b.datasources.mapValues { mutate($0) }
        out.styles = b.styles.map { chance(0.3) ? mutate($0) : $0 }
        if chance(0.1) { out.app = mutate(b.app) }
        return out
    }
}

// MARK: - Corpus

private enum FuzzCorpus {
    static func json(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func jsonFiles(_ dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Styles and templates files may hold one object or an array of them.
    static func items(_ dir: URL) -> [Any] {
        jsonFiles(dir).flatMap { url -> [Any] in
            guard let v = json(url) else { return [] }
            return (v as? [Any]) ?? [v]
        }
    }

    static func datasources(_ dir: URL) -> [String: Any] {
        var out: [String: Any] = [:]
        for sub in ["datasources", "datamocks"] {
            for url in jsonFiles(dir.appendingPathComponent(sub)) {
                if let v = json(url) { out[url.deletingPathExtension().lastPathComponent] = v }
            }
        }
        return out
    }

    /// Cases in the conformance layout under `root`.
    static func fixtureCases(root: URL) -> [(String, FuzzBundle)] {
        var cases: [(String, FuzzBundle)] = []
        let fm = FileManager.default
        let groups = (try? fm.contentsOfDirectory(atPath: root.path).sorted()) ?? []
        for group in groups {
            let groupURL = root.appendingPathComponent(group)
            let names = (try? fm.contentsOfDirectory(atPath: groupURL.path).sorted()) ?? []
            for name in names {
                let dir = groupURL.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let styles = items(dir.appendingPathComponent("styles"))
                let templates = items(dir.appendingPathComponent("templates")) + items(dir.appendingPathComponent("components"))
                let ds = datasources(dir)
                let id = "\(group)/\(name)"
                if let app = json(dir.appendingPathComponent("app.json")) {
                    var screens: [String: Any] = [:]
                    for url in jsonFiles(dir.appendingPathComponent("screens")) {
                        if let s = json(url) { screens[url.deletingPathExtension().lastPathComponent] = s }
                    }
                    guard let first = screens.keys.sorted().first else { continue }
                    let bundle = FuzzBundle(app: app, styles: styles, templates: templates, screens: screens,
                                            datasources: ds, startScreen: first)
                    // Every screen of the app is a start screen once.
                    for screen in screens.keys.sorted() {
                        cases.append(("\(id)#\(screen)", bundle.starting(at: screen)))
                    }
                } else if var screen = json(dir.appendingPathComponent("screen.json")) as? [String: Any] {
                    screen["id"] = "main-screen"
                    cases.append((id, FuzzBundle(app: FuzzBundle.synthApp(start: "main-screen"), styles: styles,
                                                 templates: templates, screens: ["main-screen": screen],
                                                 datasources: ds, startScreen: "main-screen")))
                } else if let comp = json(dir.appendingPathComponent("component.json"))
                            ?? jsonFiles(dir.appendingPathComponent("components")).first.flatMap(json) {
                    cases.append((id, wrap(component: comp, styles: styles, templates: templates, datasources: ds)))
                }
            }
        }
        return cases
    }

    static func wrap(component: Any, styles: [Any] = [], templates: [Any] = [], datasources: [String: Any] = [:]) -> FuzzBundle {
        let screen: [String: Any] = ["type": "screen", "id": "main-screen",
                                     "content": ["children": [component]]]
        return FuzzBundle(app: FuzzBundle.synthApp(start: "main-screen"), styles: styles, templates: templates,
                          screens: ["main-screen": screen], datasources: datasources, startScreen: "main-screen")
    }

    /// docs/dsl examples that are components (objects with a `type` and `content`).
    static func docExampleCases() -> [(String, FuzzBundle)] {
        let docs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/dsl")
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: docs.path)) ?? [])
            .filter { $0.hasSuffix(".md") }.sorted()
        var cases: [(String, FuzzBundle)] = []
        for file in files {
            guard let examples = try? MarkdownJSONExtractor.extract(from: docs.appendingPathComponent(file).path) else { continue }
            for (i, example) in examples.enumerated() {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(example.json.utf8)) as? [String: Any],
                      let type = obj["type"] as? String, obj["content"] != nil else { continue }
                if type == "screen" {
                    var screen = obj
                    screen["id"] = "main-screen"
                    cases.append(("docs/\(file)#\(i)", FuzzBundle(app: FuzzBundle.synthApp(start: "main-screen"),
                                  styles: [], templates: [], screens: ["main-screen": screen],
                                  datasources: [:], startScreen: "main-screen")))
                } else if type != "tabBarScreen" {
                    cases.append(("docs/\(file)#\(i)", wrap(component: obj)))
                }
            }
        }
        return cases
    }

    /// Hand-written bundles for the paths docs examples don't reach.
    static func builtInCases() -> [(String, FuzzBundle)] {
        let card: [String: Any] = ["type": "view", "id": "Card", "content": [
            "layout": ["height": 80],
            "children": [["type": "label", "id": "t", "content": [
                "properties": ["text": "{{ item.title }}"],
                "layout": ["top": 8, "leading": 12, "trailing": -12]]]]]]
        let items: [Any] = (0..<12).map { ["title": "Item \($0)", "price": $0 * 3, "image": "img\($0).jpg"] }
        let collection: [String: Any] = ["type": "collection", "id": "grid", "content": [
            "layout": ["top": 0, "leading": 0, "trailing": 0, "bottom": 0],
            "properties": ["items": "{{ items }}", "layout": ["type": "grid", "columns": 2, "spacing": 8]],
            "sections": [
                ["id": "s1", "items": "{{ items }}", "template": "Card"],
                ["id": "s2", "items": "{{ items }}", "template": ["type": "Card"]],
            ],
            "template": ["type": "Card"]]]
        let pager: [String: Any] = ["type": "collection", "id": "pager", "content": [
            "layout": ["top": 0, "leading": 0, "trailing": 0, "height": 200],
            "properties": ["items": "{{ items }}", "paging": true, "selectedIndex": "{{ page }}",
                           "layout": ["type": "horizontal", "itemWidth": "100%"]],
            "template": ["type": "Card"]]]
        let screen: [String: Any] = ["type": "screen", "id": "main-screen", "content": [
            "navigationBar": ["title": "{{ title }}"],
            "variables": ["items": ["type": "array", "initialValue": items],
                          "page": ["type": "number", "initialValue": 0],
                          "title": ["type": "string", "initialValue": "Fuzz"]],
            "children": [["type": "stackView", "id": "stack", "content": [
                "layout": ["top": 0, "leading": 0, "trailing": 0, "bottom": 0],
                "properties": ["axis": "vertical", "spacing": 8],
                "children": [pager, collection,
                             ["type": "button", "id": "b", "content": [
                                "properties": ["title": "Go"],
                                "actions": [["trigger": "tap", "type": "navigate", "screen": "missing"],
                                            ["trigger": "tap", "type": "setVariable", "name": "page", "value": "{{ page + 1 }}"]]]]]]]]]]
        let tabs: [String: Any] = ["type": "tabBarScreen", "id": "tabs", "content": [
            "tabs": [["id": "a", "label": "A", "icon": "house", "screen": "main-screen"],
                     ["id": "b", "label": "B", "icon": "bag", "screen": "missing-screen"]],
            "initialTab": "a"]]
        let base = FuzzBundle(app: FuzzBundle.synthApp(start: "main-screen"), styles: [], templates: [card],
                              screens: ["main-screen": screen, "tabs": tabs], datasources: [:], startScreen: "main-screen")
        // A template that contains itself, directly and through a collection.
        let loop: [String: Any] = ["type": "view", "id": "Loop", "content": [
            "layout": ["height": 20],
            "children": [["type": "Loop", "id": "again"],
                         ["type": "collection", "id": "nested", "content": [
                            "properties": ["items": [1, 2]], "template": ["type": "Loop"]]]]]]
        let loopScreen: [String: Any] = ["type": "screen", "id": "loop", "content": [
            "children": [["type": "Loop", "id": "first"]]]]
        var selfRef = base
        selfRef.templates.append(loop)
        selfRef.screens["loop"] = loopScreen
        return [("builtin/collections", base), ("builtin/tabs", base.starting(at: "tabs")),
                ("builtin/self-reference", selfRef.starting(at: "loop"))]
    }
}

// MARK: - Test

@MainActor
final class RobustnessFuzzTests: XCTestCase {

    /// FNV-1a: the same value on every run (Swift's `hashValue` is randomized).
    private static func stableHash(_ s: String) -> UInt64 {
        s.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }

    private static func log(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    private func run(_ bundle: FuzzBundle, window: UIWindow) async -> Bool {
        let instance = App8.instance(dataSource: FuzzDataSource(bundle))
        defer { window.rootViewController = nil }
        do {
            let root = try await instance.startApp()
            window.rootViewController = root
            window.layoutIfNeeded()
            // Let async loads (datasources, deferred sections, cells) land.
            for _ in 0..<3 {
                try? await Task.sleep(nanoseconds: 40_000_000)
                window.layoutIfNeeded()
            }
            return true
        } catch {
            // A thrown error is a handled failure (error screen), not a crash.
            return false
        }
    }

    func testEveryBundleSurvivesMutations() async throws {
        let env = ProcessInfo.processInfo.environment
        let rounds = Int(env["APP8_FUZZ_ROUNDS"] ?? "") ?? 3
        let baseSeed = UInt64(env["APP8_FUZZ_SEED"] ?? "") ?? 1120

        var cases = FuzzCorpus.builtInCases() + FuzzCorpus.docExampleCases()
        for root in (env["APP8_FUZZ_FIXTURES"] ?? "").split(separator: ":") where !root.isEmpty {
            cases += FuzzCorpus.fixtureCases(root: URL(fileURLWithPath: String(root)))
            executionTimeAllowance = 3600   // a full fixture corpus takes more than the default 10 min
        }
        // APP8_FUZZ_SHARD="i/n": run every n-th case starting at i (split long corpora).
        if let shard = env["APP8_FUZZ_SHARD"]?.split(separator: "/").compactMap({ Int($0) }), shard.count == 2, shard[1] > 0 {
            cases = cases.enumerated().filter { $0.offset % shard[1] == shard[0] }.map(\.element)
        }
        // APP8_FUZZ_START=<case id>: resume from that case (after fixing a crash).
        if let start = env["APP8_FUZZ_START"], let i = cases.firstIndex(where: { $0.0 == start }) {
            cases.removeFirst(i)
        }
        XCTAssertFalse(cases.isEmpty)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.makeKeyAndVisible()
        var started = 0, renders = 0
        for (id, bundle) in cases {
            for round in 0...rounds {
                // Seeded from the case id, so a seed reproduces under any shard.
                let seed = baseSeed &+ Self.stableHash(id) % 1_000_000 &* 1_000 &+ UInt64(round)
                var variant = bundle
                if round > 0 {
                    var mutator = Mutator(rng: SeededRandom(seed: seed), rate: round == 1 ? 0.04 : 0.12)
                    variant = mutator.mutate(bundle)
                }
                Self.log("fuzz: \(id) seed \(round == 0 ? "none" : String(seed))")
                renders += 1
                if await run(variant, window: window) { started += 1 }
            }
        }
        Self.log("fuzz: done, \(cases.count) cases, \(renders) renders, \(started) started, \(renders - started) error screens")
    }
}
