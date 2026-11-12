import CryptoKit
import DeviceCheck
import Foundation
import os
import WellSpentREST

/// What a protected request (register, login) carries: a proof, or why there isn't one (#121).
struct AppAttestResult {
    var assertion: AppAttestAssertion?
    var unavailable: AppAttestUnavailable?
}

/// Apple App Attest: attests one key per install with the server, then signs each protected request with it.
@MainActor
final class AppAttestClient {
    private static let logger = AppLogger.logger("AppAttest")

    private let service: DCAppAttestService
    private let keyIDStore: KeychainTokenStore
    private let restClient: WellSpentREST.Client

    init(
        restClient: WellSpentREST.Client,
        service: DCAppAttestService = .shared,
        keyIDStore: KeychainTokenStore = KeychainTokenStore(service: "com.bewellspent.WellSpent.appAttestKeyID")
    ) {
        self.restClient = restClient
        self.service = service
        self.keyIDStore = keyIDStore
    }

    /// The SHA-256 the assertion signs; must match the backend's `AppAttestGate.ClientDataHash`.
    nonisolated static func clientDataHash(action: String, email: String, challenge: String) -> Data {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Data(SHA256.hash(data: Data("\(action)|\(normalized)|\(challenge)".utf8)))
    }

    /// Never throws: any failure becomes an `unavailable` reason, which the server allows at a tighter limit.
    func proof(action: String, email: String) async -> AppAttestResult {
        guard service.isSupported else {
            Self.logger.info("app attest unsupported action=\(action, privacy: .public)")
            return AppAttestResult(unavailable: .unsupported)
        }
        do {
            return try await assert(action: action, email: email)
        } catch let error as DCError where error.code == .invalidKey {
            // The key is gone (reinstall, restored backup): attest a fresh one once.
            Self.logger.notice("app attest key invalid, re-attesting action=\(action, privacy: .public)")
            keyIDStore.deleteToken()
            do {
                return try await assert(action: action, email: email)
            } catch {
                return failure(error, action: action)
            }
        } catch {
            return failure(error, action: action)
        }
    }

    private func assert(action: String, email: String) async throws -> AppAttestResult {
        let keyID = try await attestedKeyID()
        let challenge = try await fetchChallenge()
        let hash = Self.clientDataHash(action: action, email: email, challenge: challenge)
        let assertion = try await service.generateAssertion(keyID, clientDataHash: hash)
        return AppAttestResult(assertion: .init(keyId: keyID, assertion: assertion.base64EncodedString(), challenge: challenge))
    }

    private func attestedKeyID() async throws -> String {
        if let existing = keyIDStore.readToken() { return existing }

        let keyID = try await service.generateKey()
        let challenge = try await fetchChallenge()
        let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
        let output = try await restClient.registerAppAttestKey(.init(body: .json(.init(
            keyId: keyID, attestation: attestation.base64EncodedString(), challenge: challenge))))
        guard case .noContent = output else {
            throw AppAttestClientError.server("key registration rejected: \(output)")
        }
        keyIDStore.save(token: keyID)
        Self.logger.info("app attest key registered keyId=\(keyID, privacy: .public)")
        return keyID
    }

    private func fetchChallenge() async throws -> String {
        let output = try await restClient.createAppAttestChallenge()
        guard case .ok(let ok) = output else {
            throw AppAttestClientError.server("challenge request failed: \(output)")
        }
        return try ok.body.json.challenge
    }

    private func failure(_ error: Error, action: String) -> AppAttestResult {
        Self.logger.error("app attest failed action=\(action, privacy: .public) error=\(String(describing: error), privacy: .public)")
        return AppAttestResult(unavailable: .service_error)
    }
}

enum AppAttestClientError: Error {
    case server(String)
}
