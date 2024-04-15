import Foundation
import JWTKit

struct Token {
    
    // https://developer.apple.com/documentation/applemusicapi/generating_developer_tokens
    struct AppleMusicConnect : JWTPayload, Equatable {
        
       func verify(using algorithm: JWTAlgorithm) async throws {
            try self.exp.verifyNotExpired()   
        }

        // The issuer (iss) registered claim key, whose value is your 10-character Team ID, obtained from your developer account
        let iss : IssuerClaim
        
        // The issued at (iat) registered claim key, whose value indicates the time at which the token was generated, in terms of the number of seconds since epoch, in UTC
        let iat : IssuedAtClaim
        
        // The expiration time (exp) registered claim key, whose value must not be greater than 15777000 (6 months in seconds) from the current Unix time on the server
        let exp : ExpirationClaim        
    }
    
    let secretKey : String
    let keyId : String
    let issuerId : String
    
    private func keys() async throws -> JWTKeyCollection {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .integerSecondsSince1970
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .integerSecondsSince1970
        let parser = DefaultJWTParser(jsonDecoder: decoder)
        let serializer = DefaultJWTSerializer(jsonEncoder: encoder)

        let key = try ES256PrivateKey(pem: secretKey)
        let keys = JWTKeyCollection()
				await keys.addES256(key: key, kid: JWKIdentifier(string: keyId), parser: parser, serializer: serializer)
        return keys 
    }

    func generate() async throws -> String {
        
        let payload = AppleMusicConnect(iss: .init(value: issuerId),
                                             iat: .init(value: .now),
                                             exp: .init(value: .init(timeIntervalSinceNow: 1*24*60*60)) // 1 day
                                            )
        let jwt = try await keys().sign(payload, kid: JWKIdentifier(string: keyId))

        return jwt
    }

		func validate(token: String?) async -> Bool {
      guard let token,
            let _ = try? await keys().verify(token, as: AppleMusicConnect.self) else {
        return false
      }
      return true
		} 
}
