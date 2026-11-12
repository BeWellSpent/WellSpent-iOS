import Foundation

/// The backend's password requirements, one checkable rule each, so Register can tick them off as you type.
nonisolated enum PasswordRule: CaseIterable, Hashable {
    case length
    case mixedCase
    case digit
    case symbol

    func isMet(by password: String) -> Bool {
        switch self {
        case .length: password.count >= 8
        case .mixedCase: password.contains(where: \.isUppercase) && password.contains(where: \.isLowercase)
        case .digit: password.contains(where: \.isNumber)
        case .symbol: password.contains { $0.isPunctuation || $0.isSymbol }
        }
    }

    var label: String {
        let locale = AppLanguageStore.currentLocale
        switch self {
        case .length: return String(localized: "8+ characters", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .mixedCase: return String(localized: "Upper & lower case", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .digit: return String(localized: "A number", bundle: AppLanguageStore.currentBundle, locale: locale)
        case .symbol: return String(localized: "A symbol", bundle: AppLanguageStore.currentBundle, locale: locale)
        }
    }
}
