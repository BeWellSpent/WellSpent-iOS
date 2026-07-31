import Foundation
import Testing
@testable import WellSpent

@Suite("JWT")
struct JWTTests {
    @Test("decodes subject and expiry from a well-formed token")
    func decodesValidToken() {
        let expiry = Date().addingTimeInterval(3600)
        let token = makeJWT(subject: "user-42", expiresAt: expiry)

        let claims = JWT.decode(token)

        #expect(claims?.subject == "user-42")
        #expect(claims?.expiresAt?.timeIntervalSince1970.rounded() == expiry.timeIntervalSince1970.rounded())
        #expect(claims?.isExpired == false)
    }

    @Test("a token whose exp is in the past is expired")
    func pastExpiryIsExpired() {
        let token = makeJWT(expiresAt: Date().addingTimeInterval(-60))
        #expect(JWT.decode(token)?.isExpired == true)
    }

    @Test("a token expiring exactly now counts as expired")
    func exactlyNowIsExpired() {
        let claims = JWT.Claims(subject: "user", expiresAt: Date())
        #expect(claims.isExpired == true)
    }

    @Test("a token with no exp claim is treated as expired")
    func missingExpiryIsExpired() {
        let token = makeJWT(expiresAt: nil)
        #expect(JWT.decode(token)?.isExpired == true)
    }

    @Test("malformed tokens (wrong segment count) fail to decode")
    func malformedSegmentCountReturnsNil() {
        #expect(JWT.decode("not-a-jwt") == nil)
        #expect(JWT.decode("only.two") == nil)
        #expect(JWT.decode("") == nil)
    }

    @Test("a token with a non-base64 payload segment fails to decode")
    func invalidBase64PayloadReturnsNil() {
        #expect(JWT.decode("header.not!!valid!!base64.signature") == nil)
    }

    @Test("a token whose payload isn't valid JSON fails to decode")
    func nonJSONPayloadReturnsNil() {
        let payload = Data("not json".utf8).base64EncodedString()
        #expect(JWT.decode("header.\(payload).signature") == nil)
    }
}
