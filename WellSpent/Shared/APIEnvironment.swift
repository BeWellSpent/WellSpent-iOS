import Foundation

/// Backend base URL for the current build configuration. Debug defaults to the
/// local dev server (`WellSpent-backend`'s `make run`, port 8080). Release
/// points at the real production backend (`API_BASE_URL` build setting in
/// `project.pbxproj`, Cloud Run — same instance web's production build uses).
nonisolated enum APIEnvironment {
    static var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String) ?? "http://localhost:8080"
    }
}
