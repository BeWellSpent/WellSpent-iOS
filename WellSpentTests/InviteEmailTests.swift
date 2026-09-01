import Foundation
import Testing
import WellSpentAPI
@testable import WellSpent

@Suite("InviteEmail")
struct InviteEmailTests {
    @Test("accepts ordinary addresses")
    func acceptsValid() {
        #expect(InviteEmail.isValid("jane@example.com"))
        #expect(InviteEmail.isValid("  jane.doe+budget@sub.example.co.uk  "))
    }

    @Test("rejects the typos it exists to catch")
    func rejectsTypos() {
        #expect(!InviteEmail.isValid("jane"))
        #expect(!InviteEmail.isValid("jane@"))
        #expect(!InviteEmail.isValid("jane@example"))
        #expect(!InviteEmail.isValid("@example.com"))
        #expect(!InviteEmail.isValid("jane example@test.com"))
        #expect(!InviteEmail.isValid("jane@example."))
    }

    // Blank is "no invite", not "bad invite" — the caller decides, but the
    // validator must not claim a blank address is usable.
    @Test("treats blank as invalid")
    func rejectsBlank() {
        #expect(!InviteEmail.isValid(""))
        #expect(!InviteEmail.isValid("   "))
    }

    // Admin can remove whoever invited them. Web's INVITABLE_ROLES excludes it
    // too; if these two ever disagree, one client can hand out a role the
    // other cannot.
    @Test("does not offer Admin, matching web")
    func excludesAdmin() {
        #expect(!InviteEmail.invitableRoles.contains(.admin))
        #expect(InviteEmail.invitableRoles == [.collaborator, .viewer])
    }

    @Test("describes each offered role")
    func describesRoles() {
        for role in InviteEmail.invitableRoles {
            #expect(!InviteEmail.roleDescription(for: role).isEmpty)
        }
        #expect(InviteEmail.roleDescription(for: .viewer) != InviteEmail.roleDescription(for: .collaborator))
    }
}

@Suite("ProfileCompletion")
struct ProfileCompletionTests {
    // The one field no social sign-up supplies: ExchangeGoogleCode and
    // SignInWithApple never receive a country, only Register does.
    @Test("a missing country is incomplete")
    func missingCountry() {
        #expect(!ProfileCompletion.isComplete(countryCode: ""))
        #expect(!ProfileCompletion.isComplete(countryCode: "   "))
    }

    @Test("any country is complete")
    func withCountry() {
        #expect(ProfileCompletion.isComplete(countryCode: "US"))
        #expect(ProfileCompletion.isComplete(countryCode: "AR"))
    }

    // State and filing status are US-only. Requiring them would gate every
    // non-US account on a question with no valid answer.
    @Test("does not require US-only fields")
    func nonUSIsComplete() {
        #expect(ProfileCompletion.isComplete(countryCode: "ES"))
    }
}
