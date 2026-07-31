import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("TaxPaymentFrequencyLabel")
struct TaxPaymentFrequencyLabelTests {
    @Test("every selectable frequency has a non-empty, distinct label")
    func selectableFrequenciesHaveDistinctLabels() {
        let labels = TaxPaymentFrequencyLabel.selectable.map { TaxPaymentFrequencyLabel.text(for: $0) }
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
    }

    @Test("unspecified and unrecognized are handled distinctly from selectable frequencies")
    func unspecifiedAndUnrecognizedAreHandled() {
        #expect(TaxPaymentFrequencyLabel.text(for: .unspecified) == "Not set")
        #expect(TaxPaymentFrequencyLabel.text(for: .UNRECOGNIZED(99)) == "Unknown")
    }
}
