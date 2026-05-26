import Foundation

/// Current App8Engine version, stamped into every event at bus dispatch time
/// (`App8AnalyticsBus.dispatch` / `App8EventBus.dispatch` stamp this onto the
/// outgoing event's `engineVersion` field so dashboards can slice by SDK
/// version without per-call plumbing).
///
/// **The value is written by the release tooling, not by hand.** The release
/// flow bumps this constant in the same commit that tags the new version, so
/// the runtime value and the SPM tag always match. Mirrors the cloud SDK's
/// `Sources/App8Cloud/Internal/SDKVersion.swift` pattern.
///
/// In a fresh source-tree checkout between releases, this carries the
/// `"0.0.0-dev"` sentinel — events fired in development carry that string
/// rather than a stale-but-plausible version number.
enum EngineVersion {
    static let current = "0.2.6"
}
