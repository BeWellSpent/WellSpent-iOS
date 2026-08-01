/// `AlertSubscription.channel` is a plain string on the wire (`notification.proto`).
nonisolated enum AlertChannel: String, CaseIterable {
    case inApp = "in_app"
    case email
    case both

    var label: String {
        switch self {
        case .inApp: return "In-App"
        case .email: return "Email"
        case .both: return "Both"
        }
    }
}
