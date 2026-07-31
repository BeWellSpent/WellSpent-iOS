import WellSpentAPI

/// Display text for a `PaymentType`.
nonisolated enum PaymentTypeLabel {
    static func text(for type: Wellspent_V1_PaymentType) -> String {
        switch type {
        case .unspecified: return "Unspecified"
        case .cash: return "Cash"
        case .credit: return "Credit"
        case .debit: return "Debit"
        case .digitalWallet: return "Digital Wallet"
        case .bankTransfer: return "Bank Transfer"
        case .crypto: return "Crypto"
        case .investment: return "Investment"
        case .other: return "Other"
        case .UNRECOGNIZED: return "Unknown"
        }
    }

    /// All selectable types, in display order, for pickers.
    static let selectable: [Wellspent_V1_PaymentType] = [
        .cash, .credit, .debit, .digitalWallet, .bankTransfer, .crypto, .investment, .other,
    ]
}
