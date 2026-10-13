import Foundation

/// Backend base URL for the current build configuration. Debug defaults to the
/// local dev server (`WellSpent-backend`'s `make run`, port 8080). Release
/// points at the real production backend (`API_BASE_URL` build setting in
/// `project.pbxproj`, Cloud Run — same instance web's production build uses).
nonisolated enum APIEnvironment {
    static var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://localhost:8080"
    }

    /// The C# rewrite's base URL (issue #78), used only for a domain whose
    /// feature flag (`FeatureFlags.csharpStatusChangelogEnabled`, etc.) is on.
    /// `CSHARP_API_BASE_URL` build setting — currently `http://localhost:5021`
    /// on **both** Debug and Release, since the C# backend has no Cloud Run
    /// deployment yet. Repoint Release once one exists, same gap API_BASE_URL
    /// itself once had (see this repo's CLAUDE.md, "Release's API_BASE_URL
    /// was still localhost").
    static var csharpBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "CSharpAPIBaseURL") as? String) ?? "http://localhost:5021"
    }
}
