import UIKit
import Combine

public extension App8 {

    /// Current screen context within the app's navigation hierarchy
    struct ScreenContext: Sendable, Equatable {
        public let screenId: String
        public let title: String?
        public let flowId: String

        public init(screenId: String, title: String?, flowId: String) {
            self.screenId = screenId
            self.title = title
            self.flowId = flowId
        }
    }

    @MainActor
    protocol Instance: AnyObject {
        func startApp() async throws -> UIViewController
        func stopApp()

        /// Publishes the currently visible screen context within the navigation hierarchy
        var screenContext: AnyPublisher<App8.ScreenContext, Never> { get }

        // Independent screen rendering
        func renderScreen(screenId: String, options: ScreenRenderOptions) async throws -> UIViewController
        func screenshotScreen(screenId: String, options: ScreenRenderOptions) async throws -> UIImage

        // MARK: - Per-instance services (formerly process-wide singletons)

        /// Engine logging level. Default `.none`. Set to `.debug` during development
        /// to see render/decode/streaming logs printed to stdout.
        var logLevel: A8Log.Level { get set }

        /// User interface style override applied to every screen rendered by this
        /// instance. Default `.unspecified` (inherit from system / host).
        var userInterfaceStyle: UIUserInterfaceStyle { get set }

        /// Layout-inspection debug mode. When `true`, components render as
        /// semi-transparent boxes to verify layout structure. Default `false`.
        var layoutModeEnabled: Bool { get set }

        /// Whether layout-mode shows component-id labels in corners. Default `true`.
        var layoutModeShowsLabels: Bool { get set }

        // MARK: - Localisation

        /// Override the active locale used when resolving `{"$i18n": "..."}` text
        /// values and locale-sensitive expression formatters (currency, number,
        /// date). Pass `nil` to revert to the device's first preferred language.
        ///
        /// The change is visible on the **next** render — already-rendered text
        /// is not re-resolved in v1. Callers that need live re-rendering can
        /// pop and re-push the current screen.
        func setLocale(_ locale: String?)

        /// The locale currently used for translation lookup and formatter
        /// output. Returns the override if one was set via `setLocale(_:)`,
        /// otherwise the device default, otherwise the app's default_locale.
        var currentLocale: String { get }

        // MARK: - Asset discovery

        /// Walks the decoded DSL tree for `screenId` and returns every
        /// remote-image asset reference and font (PostScript-name +
        /// optional face asset) the screen requires. Internally calls
        /// `ensureInfrastructureReady()` so app-level styles / templates
        /// / font families are available for font-asset resolution.
        /// Results are deduplicated.
        ///
        /// Partners (typically a cloud-delivery SDK) use this to prefetch
        /// only what's actually referenced — image bytes for `image`
        /// components, font bytes for fonts referenced by `text.fontFamily`
        /// or `font.family.displayName` — instead of eagerly downloading
        /// every asset declared by the asset manifest.
        func collectAssetReferences(screenId: String) async throws -> App8.AssetReferenceSet

        /// Walks every screen reachable from the app manifest's flows
        /// (each `navigation.flows[].startScreen` plus screens linked via
        /// actions, tabs, navigation bar, collection templates) and
        /// unions their asset references. For boot-time "prefetch the
        /// whole app" flows. Per-screen decode failures are silently
        /// skipped so a single broken screen doesn't abort the batch.
        func collectAllAssetReferences() async throws -> App8.AssetReferenceSet

        /// Returns every screen id reachable from the app manifest — the
        /// `startScreen` of each `navigation.flows[]` entry plus screens
        /// linked transitively via actions, tabs, navigation bar items,
        /// and collection templates. Cloud-delivery SDKs use this to
        /// warm the full app graph rather than just the flow entry
        /// points. Per-screen load failures are silently skipped so a
        /// single broken screen doesn't abort discovery.
        func discoverAllReachableScreenIds() async throws -> [String]
    }

    @MainActor
    protocol DebugInstance: Instance {
        var debug: App8.DebugProtocol { get }

        // Screen analysis
        func analyzeScreen(screenId: String) async throws -> ScreenAnalysis
        func getAllScreenManifest() async throws -> [ScreenManifestEntry]

        /// Renders a screen with host-supplied safe-area insets, for tooling that
        /// renders screens onto a transformed / zoomed canvas (e.g. the App8 design
        /// canvas), where UIKit's propagated safe area is unreliable.
        ///
        /// The supplied insets are ADDED to the screen's live `safeAreaInsets`
        /// (alongside any `additionalSafeAreaInsets` declared by the DSL). This
        /// assumes the host renders into a container whose real safe area is ~zero
        /// — against a normal window with non-zero system insets the values would
        /// double-count. Non-finite or negative components are sanitized to 0.
        ///
        /// Not part of the production `Instance` API.
        func renderScreen(screenId: String, options: ScreenRenderOptions,
                          fixedSafeAreaInsets: UIEdgeInsets) async throws -> UIViewController
    }
}
