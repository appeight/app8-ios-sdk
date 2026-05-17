//
//  AssetReferenceCollector.swift
//  App8Engine
//
//  Walks a decoded screen tree (or app manifest) and collects every remote-image
//  asset and font reference it requires, surfacing them as public `App8` types so
//  the internal DSL model never leaks across the API boundary. Asset/font matching
//  uses generic `Mirror` reflection, so a new component embedding a `DSL.Model.Asset`
//  or `TextModel` is picked up automatically.
//

import Foundation

/// Per-call font-face resolver: given a PostScript name, return the
/// asset declaring that face if the app's decoded styles know about it.
typealias FontAssetResolver = @Sendable (_ postScriptName: String) -> DSL.Model.Asset?

struct AssetReferenceCollector {

    private let fontAssetResolver: FontAssetResolver

    init(fontAssetResolver: @escaping FontAssetResolver) {
        self.fontAssetResolver = fontAssetResolver
    }

    /// Walk a decoded screen and return the asset + font references it holds, deduplicated.
    func collect(component: DSL.Model.Component.`Any`) -> App8.AssetReferenceSet {
        var images: Set<App8.AssetReference> = []
        var fontFamilyNames: Set<String> = []
        walkComponent(component, images: &images, fontFamilyNames: &fontFamilyNames)
        let fonts = resolveFonts(fontFamilyNames)
        return App8.AssetReferenceSet(images: images, fonts: fonts)
    }

    /// Walks every screen reachable from the app manifest's flows via BFS and unions
    /// per-screen reference sets. Per-screen load failures are silently skipped — a
    /// single broken screen must never abort a partner's prefetch.
    @MainActor
    func collectForApp(
        _ app: DSL.Model.App,
        loadScreen: @escaping @Sendable (_ id: String) async throws -> DSL.Model.Component.`Any`
    ) async -> App8.AssetReferenceSet {
        var visited = Set<String>()
        var queue: [String] = []
        for flow in app.navigation?.flows ?? [] {
            if visited.insert(flow.startScreen).inserted {
                queue.append(flow.startScreen)
            }
        }

        var images: Set<App8.AssetReference> = []
        var fontFamilyNames: Set<String> = []

        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let component = try? await loadScreen(id) else { continue }
            walkComponent(
                component,
                images: &images,
                fontFamilyNames: &fontFamilyNames,
                visitedScreens: &visited,
                queue: &queue
            )
        }
        let fonts = resolveFonts(fontFamilyNames)
        return App8.AssetReferenceSet(images: images, fonts: fonts)
    }

    private func walkComponent(
        _ component: DSL.Model.Component.`Any`,
        images: inout Set<App8.AssetReference>,
        fontFamilyNames: inout Set<String>
    ) {
        // Dummy visited/queue: not BFS-ing across screens on this path.
        var visited = Set<String>()
        var queue: [String] = []
        walkComponent(
            component,
            images: &images,
            fontFamilyNames: &fontFamilyNames,
            visitedScreens: &visited,
            queue: &queue
        )
    }

    private func walkComponent(
        _ component: DSL.Model.Component.`Any`,
        images: inout Set<App8.AssetReference>,
        fontFamilyNames: inout Set<String>,
        visitedScreens: inout Set<String>,
        queue: inout [String]
    ) {
        reflectionWalk(component.base, images: &images, fontFamilyNames: &fontFamilyNames)

        // TabBarScreen tabs hold screen ids, not components; the BFS path enqueues them.
        if let tabEntity = component.base as? DSL.Model.Component.ConcreteEntity<DSL.Model.Component.TabBarScreen.C> {
            for tab in tabEntity.content.tabs {
                if visitedScreens.insert(tab.screen).inserted {
                    queue.append(tab.screen)
                }
            }
        }

        guard let entity = component.base as? (any DSL.Model.Component.Entity) else { return }
        let content = entity.content

        for child in content.children {
            walkComponent(
                child,
                images: &images,
                fontFamilyNames: &fontFamilyNames,
                visitedScreens: &visitedScreens,
                queue: &queue
            )
        }

        // Collection template + state views
        if let collectionEntity = component.base as? DSL.Model.Component.ConcreteEntity<CollectionContent> {
            let cc = collectionEntity.content
            if let template = cc.template {
                walkComponent(template, images: &images, fontFamilyNames: &fontFamilyNames,
                              visitedScreens: &visitedScreens, queue: &queue)
            }
            for (_, ref) in cc.templates ?? [:] {
                if case .inline(let tpl) = ref {
                    walkComponent(tpl, images: &images, fontFamilyNames: &fontFamilyNames,
                                  visitedScreens: &visitedScreens, queue: &queue)
                }
            }
            if let empty = cc.emptyState {
                walkComponent(empty, images: &images, fontFamilyNames: &fontFamilyNames,
                              visitedScreens: &visitedScreens, queue: &queue)
            }
            if let loading = cc.loadingState {
                walkComponent(loading, images: &images, fontFamilyNames: &fontFamilyNames,
                              visitedScreens: &visitedScreens, queue: &queue)
            }
            if let errorView = cc.errorState {
                walkComponent(errorView, images: &images, fontFamilyNames: &fontFamilyNames,
                              visitedScreens: &visitedScreens, queue: &queue)
            }
            if let header = cc.defaultSectionHeader {
                walkComponent(header, images: &images, fontFamilyNames: &fontFamilyNames,
                              visitedScreens: &visitedScreens, queue: &queue)
            }
            for (_, header) in cc.sectionHeaders ?? [:] {
                walkComponent(header, images: &images, fontFamilyNames: &fontFamilyNames,
                              visitedScreens: &visitedScreens, queue: &queue)
            }
        }

        // Navigation-bar titleView is a component subtree outside `content.children`.
        if let navBar = extractNavigationBar(from: content),
           let titleView = navBar.titleView {
            walkComponent(titleView, images: &images, fontFamilyNames: &fontFamilyNames,
                          visitedScreens: &visitedScreens, queue: &queue)
        }

        // Action chains may target other screens (BFS only).
        if let actions = content.actions {
            for (_, action) in actions {
                enqueueScreenRefs(from: action, visitedScreens: &visitedScreens, queue: &queue)
            }
        }
        if let eventTriggers = (content as? DSL.Model.EventTriggersHolder)?.onEvent {
            for trigger in eventTriggers {
                enqueueScreenRefs(from: trigger.action, visitedScreens: &visitedScreens, queue: &queue)
            }
        }
        if let navBar = extractNavigationBar(from: content) {
            if let left = navBar.leftAction { enqueueScreenRefs(from: left.action, visitedScreens: &visitedScreens, queue: &queue) }
            if let right = navBar.rightAction { enqueueScreenRefs(from: right.action, visitedScreens: &visitedScreens, queue: &queue) }
            for barAction in navBar.rightActions ?? [] {
                enqueueScreenRefs(from: barAction.action, visitedScreens: &visitedScreens, queue: &queue)
            }
        }
    }

    /// Generic recursive Mirror walk over decoded models, picking up image assets,
    /// `DSL.Model.Asset` values, and `TextModel` font references.
    /// Depth-cap (32) guards against pathological cycles; real DSL trees nest much shallower.
    private func reflectionWalk(
        _ value: Any,
        images: inout Set<App8.AssetReference>,
        fontFamilyNames: inout Set<String>,
        depth: Int = 0
    ) {
        if depth > 32 { return }

        // Direct hits — handle before mirroring to avoid double-visiting wrapped fields.
        if let asset = value as? DSL.Model.Asset {
            insert(asset: asset, into: &images)
            return
        }
        if let imageProps = value as? DSL.Model.Component.Image.Properties {
            if case .remoteAsset(let asset) = imageProps.model {
                insert(asset: asset, into: &images)
            }
            return
        }
        if let textModel = value as? DSL.Model.Style.TextModel {
            captureTextModelFonts(textModel, into: &fontFamilyNames)
            mirrorChildren(of: textModel, images: &images, fontFamilyNames: &fontFamilyNames, depth: depth)
            return
        }
        if let family = value as? DSL.Model.Style.Font.Family {
            // Face assets are deliberately NOT added to the image set; they are
            // surfaced via the FontReference path through `resolveFonts(_:)`.
            for face in family.faces ?? [] {
                fontFamilyNames.insert(face.postScriptName)
            }
            return
        }

        mirrorChildren(of: value, images: &images, fontFamilyNames: &fontFamilyNames, depth: depth)
    }

    private func mirrorChildren(
        of value: Any,
        images: inout Set<App8.AssetReference>,
        fontFamilyNames: inout Set<String>,
        depth: Int
    ) {
        let mirror = Mirror(reflecting: value)
        if mirror.children.isEmpty { return }
        for child in mirror.children {
            reflectionWalk(child.value, images: &images, fontFamilyNames: &fontFamilyNames, depth: depth + 1)
        }
    }

    private func insert(asset: DSL.Model.Asset, into images: inout Set<App8.AssetReference>) {
        // Skip refs with unresolved `{{var}}` placeholders — not prefetchable.
        let id = asset.id.flatMap { $0.contains("{{") ? nil : $0 }
        let name = asset.name.flatMap { $0.contains("{{") ? nil : $0 }
        let url = asset.url.flatMap { $0.contains("{{") ? nil : $0 }
        if id == nil && name == nil && url == nil { return }
        images.insert(App8.AssetReference(id: id, name: name, url: url))
    }

    private func captureTextModelFonts(
        _ textModel: DSL.Model.Style.TextModel,
        into names: inout Set<String>
    ) {
        if let f = textModel.fontFamily, !f.isEmpty {
            names.insert(f)
        }
        if let family = textModel.font?.family, family.isSystemFont == false {
            names.insert(family.displayName)
        }
    }

    private func resolveFonts(_ names: Set<String>) -> Set<App8.FontReference> {
        var refs: Set<App8.FontReference> = []
        for name in names {
            let asset = fontAssetResolver(name).map {
                App8.AssetReference(id: $0.id, name: $0.name, url: $0.url)
            }
            refs.insert(App8.FontReference(postScriptName: name, asset: asset))
        }
        return refs
    }

    private func enqueueScreenRefs(
        from action: DSL.Model.Action,
        visitedScreens: inout Set<String>,
        queue: inout [String]
    ) {
        if let nextScreen = action.nextScreen,
           visitedScreens.insert(nextScreen).inserted {
            queue.append(nextScreen)
        }
        if action.type == .completeFlow, let destination = action.destination,
           visitedScreens.insert(destination).inserted {
            queue.append(destination)
        }
    }

    private func extractNavigationBar(from content: any DSL.Model.Component.EntityContent) -> DSL.Model.NavigationBar? {
        if let viewContent = content as? DSL.Model.Component.Content<DSL.Model.Component.View.Properties, DSL.Model.Style.View> {
            return viewContent.navigationBar
        }
        if let collectionContent = content as? CollectionContent {
            return collectionContent.navigationBar
        }
        if let mapContent = content as? MapContent {
            return mapContent.navigationBar
        }
        return nil
    }
}
