import Foundation

/// Backend base URL for the current build configuration. Debug defaults to
/// the local dev server (port 5021). Release points at the real production
/// backend (`CSharpAPIBaseURL` build setting in `project.pbxproj`, Cloud Run).
nonisolated enum APIEnvironment {
    static var baseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "CSharpAPIBaseURL") as? String) ?? "http://localhost:5021"
    }
}
