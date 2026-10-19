import Foundation
import WellSpentAPI
import WellSpentREST

/// Converts the REST `User` schema into the same proto message every call site already consumes — mirrors web's `useMe.ts`.
nonisolated enum UserRESTMapping {
    static func proto(from user: Components.Schemas.User) -> Wellspent_V1_User {
        .with {
            $0.id = user.id
            $0.email = user.email
            $0.firstName = user.firstName ?? ""
            $0.lastName = user.lastName ?? ""
            $0.isActive = user.isActive
            $0.isVerified = user.isVerified
            $0.createdAt = SwiftProtobuf.Google_Protobuf_Timestamp(date: user.createdAt)
            $0.countryCode = user.countryCode ?? ""
            $0.stateCode = user.stateCode ?? ""
            $0.filingStatus = Wellspent_V1_FilingStatus(rawValue: user.filingStatus) ?? .unspecified
            $0.taxPaymentFrequency = Wellspent_V1_TaxPaymentFrequency(rawValue: user.taxPaymentFrequency) ?? .unspecified
            $0.language = user.language
            $0.currency = user.currency
            $0.plan = accountPlan(from: user.plan)
            $0.hasApplePrivateEmail_p = user.hasApplePrivateEmail
        }
    }

    private static func accountPlan(from plan: Components.Schemas.UserPlan) -> Wellspent_V1_AccountPlan {
        switch plan {
        case .free: return .free
        case .pro: return .pro
        case .lifetime: return .lifetime
        }
    }

    /// GetMe, normalized to the same proto message — nil on any failure, matching every call site's existing optional-success pattern.
    static func currentUser(restClient: WellSpentREST.Client) async -> Wellspent_V1_User? {
        guard let output = try? await restClient.getMe(.init()) else { return nil }
        guard case .ok(let ok) = output, let body = try? ok.body.json else { return nil }
        return proto(from: body.user)
    }
}
