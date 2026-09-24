import Foundation

/// Focused View's ownership rule: mine, or unattributed (0) — never someone else's.
enum FocusedViewFiltering {
    static func isMineOrUnattributed(_ personID: Int64, myPersonID: Int64?) -> Bool {
        personID == 0 || personID == myPersonID
    }
}
