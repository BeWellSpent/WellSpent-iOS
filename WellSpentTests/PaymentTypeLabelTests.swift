import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("PaymentTypeLabel")
struct PaymentTypeLabelTests {
    private static let knownTypes: [Wellspent_V1_PaymentType] = [
        .unspecified, .cash, .credit, .debit, .digitalWallet, .bankTransfer, .crypto, .investment, .other,
    ]

    @Test("every known type maps to a non-empty label", arguments: knownTypes)
    func labelsAreNonEmpty(type: Wellspent_V1_PaymentType) {
        #expect(!PaymentTypeLabel.text(for: type).isEmpty)
    }

    @Test("known types map to distinct labels")
    func labelsAreDistinct() {
        let labels = Set(Self.knownTypes.map { PaymentTypeLabel.text(for: $0) })
        #expect(labels.count == Self.knownTypes.count)
    }

    @Test("selectable list excludes unspecified")
    func selectableExcludesUnspecified() {
        #expect(!PaymentTypeLabel.selectable.contains(.unspecified))
    }
}
