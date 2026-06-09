import AVFoundation
import Combine
import UIKit

/// A `UIView` whose backing layer is an `AVPlayerLayer`, so the player sizes and
/// corner-clips with the view's frame instead of needing manual layout.
private final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

class CVideoView: App8BaseView<DSL.Model.Component.Video.C>, CViewProtocol {

    private var viewModel: CVideoViewModel?
    var layoutModeId: String? { viewModel?.componentPath.split(separator: ".").last.map(String.init) }
    var layoutModeContext: App8LayoutMode? { viewModel?.service.context.layoutMode }
    weak var materialView: MaterialView?
    let contentView = UIView()
    private let playerContainer = PlayerContainerView()

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?

    /// Skip redundant reloads on reuse — keyed by the resolved source (asset name / URL).
    private var lastLoadedKey: String?

    /// Drives play/pause on window changes and app foreground/background.
    private var autoplay: Bool = true

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(playerContainer)
        playerContainer.cMakeEqualToSuperview()
        playerContainer.clipsToBounds = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func configure(viewModel: CVideoViewModel, superview: UIView? = nil, animated: Bool = true) {
        self.viewModel = viewModel
        guard let superview = superview ?? self.superview else {
            return
        }
        bindLayout(viewModel.layout, in: superview, viewRegistry: viewModel.service.componentRegistry.viewRegistry, parentComponentPath: viewModel.parentPath, keyboardService: viewModel.service.context.keyboardService, animated: animated)
        bindStyle(viewModel.style, animation: viewModel.animation)
        loadVideo(viewModel: viewModel)
    }

    override func applyStyle(
        _ style: Content.Style?,
        animated: Bool = true,
        duration: TimeInterval = 0.25,
        options: UIView.AnimationOptions = [.curveEaseInOut],
        useSpring: Bool = false
    ) {
        super.applyStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)
        applyBaseStyle(style, animated: animated, duration: duration, options: options, useSpring: useSpring)

        playerContainer.playerLayer.videoGravity = style?.videoGravity ?? .resizeAspectFill

        guard !(viewModel?.service.context.layoutMode.isEnabled == true) else {
            return
        }

        // Corner radius: direct corner takes precedence over the material's corner.
        // Register the corner so a `fraction` radius is re-resolved on resize.
        if let corner = style?.corner {
            playerContainer.layer.apply(cornerStyle: corner)
            trackRelativeCorner(corner, on: playerContainer.layer)
        } else if let material = style?.material,
                  let cornerStyle = MaterialView.cornerStyle(inMaterial: material) {
            playerContainer.layer.apply(cornerStyle: cornerStyle.content)
            trackRelativeCorner(cornerStyle.content, on: playerContainer.layer)
        } else {
            playerContainer.layer.cornerRadius = 0
            trackRelativeCorner(.none, on: playerContainer.layer)
        }
    }

    // MARK: - Source loading

    private func loadVideo(viewModel: CVideoViewModel) {
        let props = viewModel.component.properties
        autoplay = props.autoplay

        // Set gravity synchronously from the current style; the reactive `applyStyle`
        // (delivered async via the style publisher) keeps it in sync on later changes.
        playerContainer.playerLayer.videoGravity = viewModel.currentStyle?.videoGravity ?? .resizeAspectFill

        // Skip playback entirely in layout-inspection mode.
        guard !viewModel.service.context.layoutMode.isEnabled else {
            teardownPlayer()
            return
        }

        switch props.model {
        case .asset(let asset):
            guard lastLoadedKey != asset.name else { return }
            lastLoadedKey = asset.name
            guard let url = VideoAssetLocator.url(forResource: asset.name) else {
                viewModel.service.context.logger.error("Video asset '\(asset.name)' not found in bundle (looked for extensions: \(VideoAssetLocator.supportedExtensions.joined(separator: ", "))). Add it to the app bundle, or run App8 diagnostics [VID001] to catch this at validation time.")
                teardownPlayer()
                return
            }
            buildPlayer(url: url, loop: props.loop, muted: props.muted)

        case .remoteAsset(let remoteAsset):
            loadRemoteVideo(remoteAsset, viewModel: viewModel, loop: props.loop, muted: props.muted)

        case .none:
            guard lastLoadedKey != nil else { return }
            lastLoadedKey = nil
            teardownPlayer()
        }
    }

    /// Resolves a `remoteAsset` video the same way images do: prefer the data
    /// source (it owns prefetched/cached bytes), writing them to a temp file for
    /// AVPlayer; fall back to a direct URL. Off-screen reuse is keyed so an
    /// in-flight load can't clobber a newer one.
    private func loadRemoteVideo(
        _ remoteAsset: DSL.Model.Asset,
        viewModel: CVideoViewModel,
        loop: Bool,
        muted: Bool
    ) {
        let resolvedName: String? = remoteAsset.name.map { viewModel.resolvePropertyToString($0) }
        let resolvedUrl: String? = remoteAsset.url
            .map { viewModel.resolvePropertyToString($0) }
            .flatMap { $0.isEmpty ? nil : $0 }
        // Effective URL: explicit `url`, or `name` if it's itself a URL.
        let effectiveUrl = resolvedUrl
            ?? (resolvedName.flatMap { $0.hasPrefix("http://") || $0.hasPrefix("https://") ? $0 : nil })

        let key = effectiveUrl ?? resolvedName ?? remoteAsset.id ?? ""
        guard lastLoadedKey != key else { return }
        lastLoadedKey = key
        teardownPlayer()

        let dataSource = viewModel.service.dataSource
        let assetId = remoteAsset.id
        Task { [weak self] in
            let ext = Self.videoExtension(for: resolvedName ?? effectiveUrl)
            let tempURL = Self.tempVideoURL(key: key, ext: ext)

            // Reuse the temp file if this asset was already materialized this session.
            if FileManager.default.fileExists(atPath: tempURL.path) {
                await self?.buildPlayerIfCurrent(key: key, url: tempURL, loop: loop, muted: muted)
                return
            }
            // AVPlayer needs a file/URL, so spill the data source's bytes to temp.
            // Write off-main — video blobs are multi-MB and would hang the UI.
            if let data = try? await dataSource.getAsset(assetId: assetId, assetName: resolvedName),
               await Task.detached(priority: .utility, operation: {
                   (try? data.write(to: tempURL, options: .atomic)) != nil
               }).value {
                await self?.buildPlayerIfCurrent(key: key, url: tempURL, loop: loop, muted: muted)
                return
            }
            if let effectiveUrl, let url = URL(string: effectiveUrl) {
                await self?.buildPlayerIfCurrent(key: key, url: url, loop: loop, muted: muted)
                return
            }
            await self?.logRemoteVideoFailure(name: resolvedName ?? assetId ?? "?")
        }
    }

    @MainActor
    private func buildPlayerIfCurrent(key: String, url: URL, loop: Bool, muted: Bool) {
        // A newer load (reuse / source change) superseded this one — drop it.
        guard lastLoadedKey == key else { return }
        buildPlayer(url: url, loop: loop, muted: muted)
    }

    @MainActor
    private func logRemoteVideoFailure(name: String) {
        viewModel?.service.context.logger.error("Video remoteAsset '\(name)' could not be resolved from the data source or a URL — rendering empty.")
        teardownPlayer()
    }

    /// A stable per-asset temp file path, so repeated loads of the same asset
    /// reuse one file instead of accumulating copies.
    private static func tempVideoURL(key: String, ext: String) -> URL {
        let safe = String(key.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        let name = safe.isEmpty ? "video" : String(safe.suffix(96))
        return URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app8-video-\(name).\(ext)")
    }

    /// Best-effort container extension for AVPlayer's type hint; defaults to mp4.
    private static func videoExtension(for source: String?) -> String {
        let ext = (source as NSString?)?.pathExtension.lowercased() ?? ""
        return ["mp4", "mov", "m4v"].contains(ext) ? ext : "mp4"
    }

    private func buildPlayer(url: URL, loop: Bool, muted: Bool) {
        let item = AVPlayerItem(url: url)
        let queuePlayer: AVQueuePlayer
        if loop {
            // AVPlayerLooper drives a gapless loop off an empty queue player.
            queuePlayer = AVQueuePlayer()
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        } else {
            queuePlayer = AVQueuePlayer(playerItem: item)
            looper = nil
        }
        queuePlayer.isMuted = muted
        player = queuePlayer
        playerContainer.playerLayer.player = queuePlayer

        if autoplay, window != nil {
            queuePlayer.play()
        }
    }

    private func teardownPlayer() {
        player?.pause()
        playerContainer.playerLayer.player = nil
        looper = nil
        player = nil
    }

    // MARK: - Lifecycle (pause/release off-screen, resume on return)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            if autoplay { player?.play() }
        } else {
            player?.pause()
        }
    }

    override func removeFromSuperview() {
        // Free the decoder when detached (e.g. recycled collection/table cell).
        // Rebuilt on the next configure/streamingUpdate.
        teardownPlayer()
        lastLoadedKey = nil
        super.removeFromSuperview()
    }

    @objc private func appDidEnterBackground() {
        player?.pause()
    }

    @objc private func appWillEnterForeground() {
        if autoplay, window != nil { player?.play() }
    }
}

// MARK: - StreamingUpdatable

extension CVideoView: StreamingUpdatable {

    @discardableResult
    func streamingUpdate(
        component: DSL.Model.Component.`Any`,
        service: ComponentService,
        parentVariableStore: VariableStoreProtocol,
        componentPath: String,
        animated: Bool
    ) -> ComponentViewModelAbstract? {
        guard let entity = component.asEntity(),
              let vm = CVideoViewModel(
                  component: entity,
                  service: service,
                  componentPath: componentPath,
                  parentVariableStore: parentVariableStore
              ) else { return nil }

        self.viewModel = vm
        bindStyle(vm.style, animation: vm.animation)
        loadVideo(viewModel: vm)
        return vm
    }
}
