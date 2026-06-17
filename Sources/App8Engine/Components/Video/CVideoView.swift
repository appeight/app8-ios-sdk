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
    /// Still shown before the first frame paints, and again after completion
    /// when `endBehavior == .showPoster`.
    private let posterImageView = UIImageView()

    /// Non-looping clips use a plain `AVPlayer` (reliably holds the last frame on
    /// pause); looping clips use an `AVQueuePlayer` driven by `looper`.
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var playbackObserver: VideoPlaybackObserver?

    /// Skip redundant reloads on reuse — keyed by the resolved source (asset name / URL).
    private var lastLoadedKey: String?

    /// Drives play/pause on window changes and app foreground/background.
    private var autoplay: Bool = true

    /// The initial (delayed) play has been kicked off — distinguishes a fresh
    /// start (honours `startDelay`) from a resume on window/foreground return.
    private var hasBegunInitialPlayback = false
    /// A non-looping clip has played to its end (drives end-behavior + replay).
    private var didComplete = false
    /// The item reached `.readyToPlay` — startup (seek / delay / play) is gated
    /// on this, since seeks and rate changes are dropped on a not-ready item.
    private var isItemReady = false
    /// Playback has actually begun (poster faded out). Distinct from
    /// `isItemReady`: during a `startDelay` the item is ready but the poster
    /// stays up until playback starts.
    private var playbackStarted = false
    /// Pending delayed start; cancelled when off-screen / backgrounded.
    private var startDelayWorkItem: DispatchWorkItem?
    /// Monotonic token so a stale async poster load can't clobber a newer one.
    private var posterGeneration = 0

    override func setup() {
        super.setup()

        addSubview(contentView)
        contentView.cMakeEqualToSuperview()

        contentView.addSubview(playerContainer)
        playerContainer.cMakeEqualToSuperview()
        playerContainer.clipsToBounds = true

        contentView.addSubview(posterImageView)
        posterImageView.cMakeEqualToSuperview()
        posterImageView.clipsToBounds = true
        posterImageView.alpha = 0

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

        let gravity = style?.videoGravity ?? .resizeAspectFill
        playerContainer.playerLayer.videoGravity = gravity
        posterImageView.contentMode = Self.posterContentMode(for: gravity)

        guard !(viewModel?.service.context.layoutMode.isEnabled == true) else {
            return
        }

        // Corner radius (same clip for the player layer and the poster). Direct
        // corner takes precedence over the material's corner; register relative
        // (`fraction`) corners so they re-resolve on resize.
        applyCorner(style, to: playerContainer.layer)
        applyCorner(style, to: posterImageView.layer)
    }

    private func applyCorner(_ style: Content.Style?, to layer: CALayer) {
        if let corner = style?.corner {
            layer.apply(cornerStyle: corner)
            trackRelativeCorner(corner, on: layer)
        } else if let material = style?.material,
                  let cornerStyle = MaterialView.cornerStyle(inMaterial: material) {
            layer.apply(cornerStyle: cornerStyle.content)
            trackRelativeCorner(cornerStyle.content, on: layer)
        } else {
            layer.cornerRadius = 0
            trackRelativeCorner(.none, on: layer)
        }
    }

    private static func posterContentMode(for gravity: AVLayerVideoGravity) -> UIView.ContentMode {
        switch gravity {
        case .resizeAspect: return .scaleAspectFit
        case .resize: return .scaleToFill
        default: return .scaleAspectFill
        }
    }

    // MARK: - Source loading

    private func loadVideo(viewModel: CVideoViewModel) {
        let props = viewModel.component.properties
        autoplay = props.autoplay

        // Set gravity synchronously from the current style; the reactive `applyStyle`
        // (delivered async via the style publisher) keeps it in sync on later changes.
        let gravity = viewModel.currentStyle?.videoGravity ?? .resizeAspectFill
        playerContainer.playerLayer.videoGravity = gravity
        posterImageView.contentMode = Self.posterContentMode(for: gravity)

        // Skip playback entirely in layout-inspection mode.
        guard !viewModel.service.context.layoutMode.isEnabled else {
            posterImageView.image = nil
            posterImageView.alpha = 0
            teardownPlayer()
            return
        }

        // Poster is (re)shown only when we actually (re)load a source — not on a
        // no-op reuse, which would flash a still over an already-playing video.
        switch props.model {
        case .asset(let asset):
            guard lastLoadedKey != asset.name else { return }
            lastLoadedKey = asset.name
            guard let url = VideoAssetLocator.url(forResource: asset.name) else {
                viewModel.service.context.logger.error("Video asset '\(asset.name)' not found in bundle (looked for extensions: \(VideoAssetLocator.supportedExtensions.joined(separator: ", "))). Add it to the app bundle, or run App8 diagnostics [VID001] to catch this at validation time.")
                hidePoster()
                teardownPlayer()
                return
            }
            buildPlayer(url: url)

        case .remoteAsset(let remoteAsset):
            loadRemoteVideo(remoteAsset, viewModel: viewModel)

        case .none:
            guard lastLoadedKey != nil else { return }
            lastLoadedKey = nil
            hidePoster()
            teardownPlayer()
        }
    }

    /// Resolves a `remoteAsset` video the same way images do: prefer the data
    /// source (it owns prefetched/cached bytes), writing them to a temp file for
    /// AVPlayer; fall back to a direct URL. Off-screen reuse is keyed so an
    /// in-flight load can't clobber a newer one.
    private func loadRemoteVideo(
        _ remoteAsset: DSL.Model.Asset,
        viewModel: CVideoViewModel
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
        // Show image-based posters during the download; frame-based posters are
        // filled in once `buildPlayer` has the resolved URL.
        showPrePlaybackPoster(videoURL: nil)

        let dataSource = viewModel.service.dataSource
        let assetId = remoteAsset.id
        Task { [weak self] in
            let ext = Self.videoExtension(for: resolvedName ?? effectiveUrl)
            let tempURL = Self.tempVideoURL(key: key, ext: ext)

            // Reuse the temp file if this asset was already materialized this session.
            if FileManager.default.fileExists(atPath: tempURL.path) {
                await self?.buildPlayerIfCurrent(key: key, url: tempURL)
                return
            }
            // AVPlayer needs a file/URL, so spill the data source's bytes to temp.
            // Write off-main — video blobs are multi-MB and would hang the UI.
            if let data = try? await dataSource.getAsset(assetId: assetId, assetName: resolvedName),
               await Task.detached(priority: .utility, operation: {
                   (try? data.write(to: tempURL, options: .atomic)) != nil
               }).value {
                await self?.buildPlayerIfCurrent(key: key, url: tempURL)
                return
            }
            if let effectiveUrl, let url = URL(string: effectiveUrl) {
                await self?.buildPlayerIfCurrent(key: key, url: url)
                return
            }
            await self?.logRemoteVideoFailure(name: resolvedName ?? assetId ?? "?")
        }
    }

    @MainActor
    private func buildPlayerIfCurrent(key: String, url: URL) {
        // A newer load (reuse / source change) superseded this one — drop it.
        guard lastLoadedKey == key else { return }
        buildPlayer(url: url)
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

    private func buildPlayer(url: URL) {
        guard let viewModel else { return }
        let props = viewModel.component.properties

        // Replace any prior player/observer first (source change on a reused view).
        teardownPlayer()

        let item = AVPlayerItem(url: url)
        let avPlayer: AVPlayer
        let loops = props.loops
        if loops {
            // AVPlayerLooper drives a gapless loop off an empty queue player.
            let queuePlayer = AVQueuePlayer()
            looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
            avPlayer = queuePlayer
        } else {
            // Plain AVPlayer holds the final frame on pause (the old
            // black-layer-on-end bug came from AVQueuePlayer draining its queue);
            // `endBehavior` decides what shows next.
            avPlayer = AVPlayer(playerItem: item)
            avPlayer.actionAtItemEnd = .pause
            looper = nil
        }
        avPlayer.isMuted = props.muted
        player = avPlayer
        playerContainer.playerLayer.player = avPlayer

        attachObserver(player: avPlayer, item: item, looper: looper, props: props)

        // Pre-playback poster now that the URL is known (covers frame-based
        // posters; `teardownPlayer` above reset playback state so it shows).
        showPrePlaybackPoster(videoURL: url)

        // Do NOT seek / set rate / play here — the item is not `.readyToPlay`
        // yet, so those calls would be dropped. Startup runs once readiness
        // fires (`handleItemReady`), or on window/foreground return if already
        // ready.
        startOrResume()
    }

    private func attachObserver(player: AVPlayer, item: AVPlayerItem, looper: AVPlayerLooper?, props: DSL.Model.Component.Video.Properties) {
        let observer = VideoPlaybackObserver()
        observer.onReadyToPlay = { [weak self] in self?.handleItemReady() }
        observer.onStart = { [weak self] in self?.viewModel?.dispatchVideoTrigger(.onVideoStart) }
        observer.onPause = { [weak self] in self?.viewModel?.dispatchVideoTrigger(.onVideoPause) }
        observer.onStall = { [weak self] in self?.viewModel?.dispatchVideoTrigger(.onVideoStall) }
        observer.onLoop = { [weak self] count in
            self?.viewModel?.dispatchVideoTrigger(.onVideoLoop, overlays: ["$loopCount": count])
        }
        observer.onError = { [weak self] message in
            self?.viewModel?.dispatchVideoTrigger(.onVideoError, overlays: message.map { ["$error": $0] } ?? [:])
        }
        observer.onComplete = { [weak self] in self?.handleComplete() }
        observer.onMark = { [weak self] id in
            self?.viewModel?.dispatchVideoTrigger(.onTimeMark, overlays: ["$markId": id])
        }
        observer.attach(
            player: player,
            item: item,
            looper: looper,
            marks: props.marks ?? [],
            loops: props.loops
        )
        playbackObserver = observer
    }

    private func teardownPlayer() {
        cancelStartDelay()
        playbackObserver?.detach()
        playbackObserver = nil
        player?.pause()
        playerContainer.playerLayer.player = nil
        looper = nil
        player = nil
        hasBegunInitialPlayback = false
        didComplete = false
        isItemReady = false
        playbackStarted = false
        playerContainer.alpha = 1
    }

    // MARK: - Playback start / resume / replay

    /// Start (honouring `startDelay`) or resume playback, or replay from the top
    /// if the clip already completed. No-op unless autoplay + on-window + the
    /// item is ready (when not yet ready, `handleItemReady` re-enters here).
    private func startOrResume() {
        guard autoplay, window != nil, player != nil, isItemReady else { return }
        if didComplete {
            replayFromStart()
        } else if hasBegunInitialPlayback {
            beginPlayback()
        } else {
            scheduleInitialPlayback()
        }
    }

    private func scheduleInitialPlayback() {
        hasBegunInitialPlayback = true
        cancelStartDelay()
        // Item is ready here, so this seek actually takes (unlike in `buildPlayer`).
        if let startTime = viewModel?.component.properties.startTime, startTime > 0 {
            player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
        let delay = viewModel?.component.properties.startDelay ?? 0
        if delay > 0 {
            let work = DispatchWorkItem { [weak self] in self?.beginPlayback() }
            startDelayWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            beginPlayback()
        }
    }

    /// Once-per-appearance replay: a finished non-looping clip plays again from
    /// the start when it returns to window / the app foregrounds.
    private func replayFromStart() {
        didComplete = false
        playbackStarted = false
        playerContainer.alpha = 1
        playbackObserver?.resetForReplay()
        let startTime = viewModel?.component.properties.startTime ?? 0
        player?.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        showPrePlaybackPoster(videoURL: (player?.currentItem?.asset as? AVURLAsset)?.url)
        beginPlayback()
    }

    /// Apply the configured rate and start. `playImmediately(atRate:)` sets the
    /// rate atomically (unlike assigning `.rate`, which can be overridden by the
    /// player's automatic playback management), so `rate` actually takes effect.
    private func beginPlayback() {
        guard let player else { return }
        let rate = viewModel?.component.properties.rate ?? 0
        player.playImmediately(atRate: rate > 0 ? rate : 1.0)
        markPlaybackStarted()
    }

    /// First real start of this play-through — fade the pre-playback poster out.
    /// Held off until here (not item-ready) so a `startDelay` shows the poster
    /// for its full duration.
    private func markPlaybackStarted() {
        guard !playbackStarted else { return }
        playbackStarted = true
        guard posterImageView.alpha != 0 else { return }
        UIView.animate(withDuration: 0.25) { self.posterImageView.alpha = 0 }
    }

    private func cancelStartDelay() {
        startDelayWorkItem?.cancel()
        startDelayWorkItem = nil
    }

    // MARK: - Playback event handlers

    /// Item reached `.readyToPlay`: fire the trigger and kick off startup (or a
    /// resume, if the view already returned to the window before readiness).
    private func handleItemReady() {
        guard !isItemReady else { return }
        isItemReady = true
        viewModel?.dispatchVideoTrigger(.onVideoReady)
        startOrResume()
    }

    private func handleComplete() {
        didComplete = true
        viewModel?.dispatchVideoTrigger(.onVideoComplete)
        switch viewModel?.component.properties.endBehavior ?? .freezeLastFrame {
        case .freezeLastFrame, .loop:
            break // last frame held by `actionAtItemEnd = .pause`
        case .hidePoster:
            playerContainer.alpha = 0
            posterImageView.alpha = 0
        case .showPoster:
            showEndPoster()
        }
    }

    // MARK: - Poster loading

    private func showPrePlaybackPoster(videoURL: URL?) {
        posterGeneration += 1
        let gen = posterGeneration
        guard let source = viewModel?.component.properties.poster else {
            posterImageView.image = nil
            posterImageView.alpha = 0
            return
        }
        posterImageView.alpha = 1   // visible immediately; the image fills in async
        Task { [weak self] in
            guard let self else { return }
            let image = await self.resolvePosterImage(source, videoURL: videoURL)
            guard gen == self.posterGeneration, !self.playbackStarted, let image else { return }
            self.posterImageView.image = image
        }
    }

    private func hidePoster() {
        posterGeneration += 1   // cancel any in-flight poster load
        posterImageView.image = nil
        posterImageView.alpha = 0
    }

    private func showEndPoster() {
        posterGeneration += 1
        let gen = posterGeneration
        let props = viewModel?.component.properties
        guard let source = props?.endPoster ?? props?.poster else { return }
        let videoURL = (player?.currentItem?.asset as? AVURLAsset)?.url
        Task { [weak self] in
            guard let self else { return }
            let image = await self.resolvePosterImage(source, videoURL: videoURL)
            guard gen == self.posterGeneration, let image else { return }
            self.posterImageView.image = image
            UIView.animate(withDuration: 0.25) { self.posterImageView.alpha = 1 }
        }
    }

    private func resolvePosterImage(_ source: DSL.Model.Component.Video.PosterSource, videoURL: URL?) async -> UIImage? {
        switch source.kind {
        case .localAsset:
            return source.name.flatMap { UIImage(named: $0) }

        case .remoteAsset, .url:
            guard let viewModel else { return nil }
            let resolvedName = source.name.map { viewModel.resolvePropertyToString($0) }
            let resolvedUrl = source.url
                .map { viewModel.resolvePropertyToString($0) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let effectiveUrl = resolvedUrl
                ?? (resolvedName.flatMap { $0.hasPrefix("http://") || $0.hasPrefix("https://") ? $0 : nil })
            if let data = try? await viewModel.service.dataSource.getAsset(assetId: source.id, assetName: resolvedName),
               let decoded = await UIImage(data: data)?.byPreparingForDisplay() {
                return decoded
            }
            if let effectiveUrl {
                return await viewModel.service.imageLoader.loadImage(urlString: effectiveUrl)
            }
            return nil

        case .firstFrame:
            return await Self.generateFrame(url: videoURL, at: 0)

        case .frameAtTime:
            return await Self.generateFrame(url: videoURL, at: source.time ?? 0)
        }
    }

    /// Render a still from the video at `seconds` for `firstFrame`/`frameAtTime`
    /// posters. Off-main; returns nil on failure (poster simply stays empty).
    nonisolated private static func generateFrame(url: URL?, at seconds: Double) async -> UIImage? {
        guard let url else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        return await withCheckedContinuation { continuation in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                continuation.resume(returning: cgImage.map { UIImage(cgImage: $0) })
            }
        }
    }

    // MARK: - Lifecycle (pause/release off-screen, resume on return)

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startOrResume()
        } else {
            cancelStartDelay()
            player?.pause()
        }
    }

    override func removeFromSuperview() {
        // Free the decoder when detached (e.g. recycled collection/table cell).
        // Rebuilt on the next configure/streamingUpdate.
        teardownPlayer()
        hidePoster()
        lastLoadedKey = nil
        super.removeFromSuperview()
    }

    @objc private func appDidEnterBackground() {
        cancelStartDelay()
        player?.pause()
    }

    @objc private func appWillEnterForeground() {
        startOrResume()
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
