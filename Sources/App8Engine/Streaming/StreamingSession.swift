import Foundation

/// Central coordinator for a streaming screen. Manages screen + datasource streams:
/// streamScreen() emissions trigger a full ScreenUpdater re-render; streamDatasource()
/// emissions inject directly into the variable store (zero re-render fast path).
/// Created by ScreenViewController after initial render, stopped on deinit.
@MainActor
final class StreamingSession {

    private let screenId: String
    private let initialComponent: DSL.Model.Component.`Any`
    private var variableStore: ScopedVariableStore
    private let dataSource: A8.DataSourceProtocol
    private let updater: ScreenUpdater
    private let styleResolver: ((String) -> (any DSL.Model.Style.Entity)?)?
    private let styleUpdater: ((Data) -> Void)?
    private let context: App8Context

    private var streamingTasks: [Task<Void, Never>] = []

    /// Last raw screen data received — stored so we can re-render after a style update.
    private var lastRawScreenData: Data?

    init(
        screenId: String,
        component: DSL.Model.Component.`Any`,
        variableStore: ScopedVariableStore,
        dataSource: A8.DataSourceProtocol,
        updater: ScreenUpdater,
        styleResolver: ((String) -> (any DSL.Model.Style.Entity)?)?,
        styleUpdater: ((Data) -> Void)? = nil,
        context: App8Context
    ) {
        self.screenId = screenId
        self.initialComponent = component
        self.variableStore = variableStore
        self.dataSource = dataSource
        self.updater = updater
        self.styleResolver = styleResolver
        self.styleUpdater = styleUpdater
        self.context = context
    }

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.userInfo[.app8Logger] = context.logger
        return d
    }

    deinit {
        // Tasks hold strong references; cancel them so streams are released promptly.
        // Task.cancel() is safe to call from any context (deinit can't hop to MainActor).
        streamingTasks.forEach { $0.cancel() }
    }

    /// Starts watching all streams (screen + streaming variables + styles).
    func start() {
        context.logger.debug("StreamingSession[\(screenId)]: starting")
        startScreenStreaming()
        startVariableStreaming(for: initialComponent)
        startStyleStreaming()
    }

    /// Cancels all active streams.
    func stop() {
        context.logger.debug("StreamingSession[\(screenId)]: stopping \(streamingTasks.count) task(s)")
        streamingTasks.forEach { $0.cancel() }
        streamingTasks.removeAll()
    }

    // MARK: - Screen Streaming

    private func startScreenStreaming() {
        guard let stream = dataSource.streamScreen(screenId: screenId) else {
            context.logger.debug("StreamingSession[\(screenId)]: no screen stream (streamScreen returned nil)")
            return
        }
        context.logger.debug("StreamingSession[\(screenId)]: subscribed to screen stream")

        let task = Task { @MainActor [weak self] in
            for await data in stream {
                guard let self, !Task.isCancelled else { break }
                context.logger.debug("StreamingSession[\(self.screenId)]: received screen update (\(data.count) bytes)")
                await self.handleScreenUpdate(data)
            }
            self?.context.logger.debug("StreamingSession[\(self?.screenId ?? "?")]: screen stream ended")
        }
        streamingTasks.append(task)
    }

    private func handleScreenUpdate(_ data: Data) async {
        lastRawScreenData = data
        do {
            var newComponent = try makeDecoder().decode(DSL.Model.Component.`Any`.self, from: data)
            if let resolver = styleResolver {
                newComponent.resolveStylePointers(resolver: resolver)
            }
            let snapshot = variableStore.getAllValues()

            if let newStore = await updater.update(
                newComponent: newComponent,
                preservedState: snapshot,
                animated: true
            ) {
                context.logger.debug("StreamingSession[\(screenId)]: screen re-rendered, store updated")
                // Future variable updates must target the new store.
                variableStore = newStore
                startVariableStreaming(for: newComponent)
            }
        } catch {
            context.logger.error("StreamingSession[\(screenId)]: failed to decode screen update: \(error)")
        }
    }

    // MARK: - Variable Streaming

    private func startVariableStreaming(for component: DSL.Model.Component.`Any`) {
        guard
            case .key(.screen) = component.type,
            let entity: DSL.Model.Component.View.Entity = component.asConcreteEntity(),
            let variables = entity.content.variables
        else { return }

        let streamingVars = variables.filter { $0.value.isStreaming }
        context.logger.debug("StreamingSession[\(screenId)]: \(streamingVars.count) streaming variable(s): \(streamingVars.keys.sorted().joined(separator: ", "))")

        for (name, definition) in streamingVars {
            guard let source = definition.source else {
                context.logger.warning("StreamingSession[\(screenId)]: variable '\(name)' has streaming=true but no source")
                continue
            }
            startDatasourceStream(variableName: name, datasourceId: source, componentPath: nil)
        }
    }

    private func startDatasourceStream(variableName: String, datasourceId: String, componentPath: String?) {
        guard let stream = dataSource.streamDatasource(
            screenId: screenId,
            datasourceId: datasourceId,
            componentPath: componentPath
        ) else {
            context.logger.warning("StreamingSession[\(screenId)]: no stream for '\(variableName)' (datasourceId=\(datasourceId)) — streamDatasource returned nil")
            return
        }
        context.logger.debug("StreamingSession[\(screenId)]: subscribed to datasource stream for '\(variableName)' (\(datasourceId))")

        let task = Task { @MainActor [weak self] in
            // Throttle: a hostile datasource must not update-storm the UI.
            let minUpdateInterval: TimeInterval = 0.05
            var lastApplied = Date.distantPast
            for await data in stream {
                guard let self, !Task.isCancelled else { break }
                let elapsed = Date().timeIntervalSince(lastApplied)
                if elapsed < minUpdateInterval {
                    try? await Task.sleep(nanoseconds: UInt64((minUpdateInterval - elapsed) * 1_000_000_000))
                    if Task.isCancelled { break }
                }
                lastApplied = Date()
                context.logger.debug("StreamingSession[\(self.screenId)]: received update for '\(variableName)' (\(data.count) bytes)")
                self.handleVariableUpdate(name: variableName, data: data)
            }
            self?.context.logger.debug("StreamingSession[\(self?.screenId ?? "?")]: stream for '\(variableName)' ended")
        }
        streamingTasks.append(task)
    }

    private func handleVariableUpdate(name: String, data: Data) {
        do {
            let definition = try makeDecoder().decode(DatasourceDefinition.self, from: data)
            context.logger.debug("StreamingSession[\(screenId)]: injecting '\(name)' = \(definition.rawData)")
            variableStore.setExternalValue(name: name, value: definition.rawData)
        } catch {
            context.logger.error("StreamingSession[\(screenId)]: failed to decode variable update for '\(name)': \(error)")
        }
    }

    // MARK: - Style Streaming

    private func startStyleStreaming() {
        guard let stream = dataSource.streamStyles() else {
            context.logger.debug("StreamingSession[\(screenId)]: no style stream (streamStyles returned nil)")
            return
        }
        context.logger.debug("StreamingSession[\(screenId)]: subscribed to style stream")

        let task = Task { @MainActor [weak self] in
            for await data in stream {
                guard let self, !Task.isCancelled else { break }
                context.logger.debug("StreamingSession[\(self.screenId)]: received style update (\(data.count) bytes)")
                await self.handleStyleUpdate(data)
            }
            self?.context.logger.debug("StreamingSession[\(self?.screenId ?? "?")]: style stream ended")
        }
        streamingTasks.append(task)
    }

    private func handleStyleUpdate(_ data: Data) async {
        styleUpdater?(data)

        // Re-render the current screen with freshly-resolved styles.
        guard let rawData = lastRawScreenData else { return }
        do {
            var component = try makeDecoder().decode(DSL.Model.Component.`Any`.self, from: rawData)
            if let resolver = styleResolver {
                component.resolveStylePointers(resolver: resolver)
            }
            let snapshot = variableStore.getAllValues()
            if let newStore = await updater.update(
                newComponent: component,
                preservedState: snapshot,
                animated: true
            ) {
                context.logger.debug("StreamingSession[\(screenId)]: screen re-rendered after style update")
                variableStore = newStore
            }
        } catch {
            context.logger.error("StreamingSession[\(screenId)]: failed to re-render after style update: \(error)")
        }
    }
}
