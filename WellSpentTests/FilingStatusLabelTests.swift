import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("FilingStatusLabel")
struct FilingStatusLabelTests {
    @Test("every selectable status has a non-empty, distinct label")
    func selectableStatusesHaveDistinctLabels() {
        let labels = FilingStatusLabel.selectable.map { FilingStatusLabel.text(for: $0) }
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == labels.count)
    }

    @Test("unspecified and unrecognized are handled distinctly from selectable statuses")
    func unspecifiedAndUnrecognizedAreHandled() {
        #expect(FilingStatusLabel.text(for: .unspecified) == "Not set")
        #expect(FilingStatusLabel.text(for: .UNRECOGNIZED(99)) == "Unknown")
    }
}
