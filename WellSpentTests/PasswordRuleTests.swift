import Testing
@testable import WellSpent

@Suite("PasswordRule")
@MainActor
struct PasswordRuleTests {
    @Test("each rule checks only its own requirement")
    func rulesAreIndependent() {
        #expect(PasswordRule.length.isMet(by: "abcdefgh"))
        #expect(!PasswordRule.length.isMet(by: "Ab1!"))
        #expect(PasswordRule.mixedCase.isMet(by: "aB"))
        #expect(!PasswordRule.mixedCase.isMet(by: "lowercase"))
        #expect(PasswordRule.digit.isMet(by: "a1"))
        #expect(!PasswordRule.digit.isMet(by: "abc"))
        #expect(PasswordRule.symbol.isMet(by: "a!"))
        #expect(!PasswordRule.symbol.isMet(by: "abc1"))
    }

    @Test("all rules met is exactly what the backend accepts")
    func allRulesMatchPasswordError() {
        for password in ["Valid1Password!", "Ab1!", "NoSpecial123", "nodigits!A", "ALLCAPS1!"] {
            let allMet = PasswordRule.allCases.allSatisfy { $0.isMet(by: password) }
            #expect(allMet == (RegisterViewModel.passwordError(for: password) == nil))
        }
    }
}
