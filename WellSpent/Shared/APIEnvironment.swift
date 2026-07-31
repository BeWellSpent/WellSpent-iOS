import Foundation

/// Backend base URL for the current build configuration. Debug defaults to the
/// local dev server (`WellSpent-backend`'s `make run`, port 8080). Release
/// currently points at the same local URL as a placeholder — the workspace has
/// no deployed backend yet (see docs/specs/01-requirements.md "Planned →
/// Deployment / CD") — update `INFOPLIST_KEY_APIBaseURL` in the Release build
/// configuration once a real URL exists.
nonisolated enum APIEnvironment {
    static var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://localhost:8080"
    }
}
