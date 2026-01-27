import Foundation
import Maxi80Backend

/// Mock JWT token factory for testing
public final class MockJWTTokenFactory: JWTTokenFactoryProtocol {

    public struct CallRecord {
        public let action: Action
        public let token: String?

        public enum Action: Equatable {
            case generateJWTString
            case validateJWTString(String?)
        }
    }

    private var callRecords: [CallRecord] = []
    private var generateTokenResponses: [Result<String, Error>] = []
    private var validateTokenResponses: [Bool] = []
    private var generateIndex = 0
    private var validateIndex = 0

    public init() {}

    public func generateJWTString() async throws -> String {
        let record = CallRecord(action: .generateJWTString, token: nil)
        callRecords.append(record)

        guard generateIndex < generateTokenResponses.count else {
            throw MockError.noResponseConfigured
        }

        let result = generateTokenResponses[generateIndex]
        generateIndex += 1

        switch result {
        case .success(let token):
            return token
        case .failure(let error):
            throw error
        }
    }

    public func validateJWTString(token: String?) async -> Bool {
        let record = CallRecord(action: .validateJWTString(token), token: token)
        callRecords.append(record)

        guard validateIndex < validateTokenResponses.count else {
            return false
        }

        let result = validateTokenResponses[validateIndex]
        validateIndex += 1
        return result
    }

    // Test helper methods
    public func setGenerateTokenResponse(_ token: String) {
        generateTokenResponses.append(.success(token))
    }

    public func setGenerateTokenError(_ error: Error) {
        generateTokenResponses.append(.failure(error))
    }

    public func setValidateTokenResponse(_ isValid: Bool) {
        validateTokenResponses.append(isValid)
    }

    public func getCallRecords() -> [CallRecord] {
        callRecords
    }

    public func reset() {
        callRecords.removeAll()
        generateTokenResponses.removeAll()
        validateTokenResponses.removeAll()
        generateIndex = 0
        validateIndex = 0
    }
}

public enum MockError: Error {
    case noResponseConfigured
    case invalidToken
}
