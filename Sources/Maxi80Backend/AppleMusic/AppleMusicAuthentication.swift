import JWTKit

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Use this struct to store the secret in AWS SecretsManager
public struct AppleMusicSecret: Codable, Sendable, CustomStringConvertible {

    // the name to store this secret on a ssecret tore manager
    public static let name = "Maxi80-AppleMusicKey"

    public var description: String { "\nTeam Id: \(teamId)\nKey Id: \(keyId)\nPrivate key: -shuuuut, it's a secret—" }

    public init(privateKey: String, teamId: String, keyId: String) {
        self.privateKey = privateKey
        self.teamId = teamId
        self.keyId = keyId
    }
    public let privateKey: String
    public let teamId: String
    public let keyId: String
}

/// Use this struct to generate JWT Tokens and authenticate API calls to Apple Music
public struct JWTTokenFactory {

    private let secretKey: String
    private let keyId: String
    private let issuerId: String

    public init(secretKey: String, keyId: String, issuerId: String) {
        self.secretKey = secretKey
        self.keyId = keyId
        self.issuerId = issuerId
    }

    private func keys() async throws -> JWTKeyCollection {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .integerSecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .integerSecondsSince1970
        let parser = DefaultJWTParser(jsonDecoder: decoder)
        let serializer = DefaultJWTSerializer(jsonEncoder: encoder)

        let key = try ES256PrivateKey(pem: secretKey)
        let keys = JWTKeyCollection()
        await keys.add(
            ecdsa: key,
            kid: JWKIdentifier(string: keyId),
            parser: parser,
            serializer: serializer
        )
        return keys
    }

    public func generateJWTString() async throws -> String {

        let payload = AppleMusicToken(
            iss: .init(value: issuerId),
            iat: .init(value: .now),
            exp: .init(value: .init(timeIntervalSinceNow: 1 * 24 * 60 * 60))  // 1 day
        )
        let jwt = try await keys().sign(payload, kid: JWKIdentifier(string: keyId))

        return jwt
    }

    public func validateJWTString(token: String?) async -> Bool {
        guard let token,
            (try? await keys().verify(token, as: AppleMusicToken.self)) != nil
        else {
            return false
        }
        return true
    }

    // https://developer.apple.com/documentation/applemusicapi/generating_developer_tokens
    private struct AppleMusicToken: JWTPayload, Equatable {
        func verify(using algorithm: some JWTKit.JWTAlgorithm) async throws {
            try self.exp.verifyNotExpired()
        }

        // The issuer (iss) registered claim key, whose value is your 10-character Team ID, obtained from your developer account
        let iss: IssuerClaim

        // The issued at (iat) registered claim key, whose value indicates the time at which the token was generated, in terms of the number of seconds since epoch, in UTC
        let iat: IssuedAtClaim

        // The expiration time (exp) registered claim key, whose value must not be greater than 15777000 (6 months in seconds) from the current Unix time on the server
        let exp: ExpirationClaim
    }

}
