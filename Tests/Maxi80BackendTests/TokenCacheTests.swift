import Testing
import Foundation
import Logging
import AWSLambdaEvents
import HTTPTypes
import NIOHTTP1
@testable import Maxi80Lambda
@testable import Maxi80Backend

@Suite("Token Cache Tests")
struct TokenCacheTests {
    
    @Test("Token factory generates JWT token")
    func testTokenFactoryGeneratesToken() async throws {
        // Given
        let mockTokenFactory = MockJWTTokenFactory()
        mockTokenFactory.setGenerateTokenResponse("test-jwt-token")
        
        // When
        let token = try await mockTokenFactory.generateJWTString()
        
        // Then
        #expect(token == "test-jwt-token")
        
        let calls = mockTokenFactory.getCallRecords()
        #expect(calls.count == 1)
        #expect(calls[0].action == .generateJWTString)
    }
    
    @Test("Token factory validates JWT token")
    func testTokenFactoryValidatesToken() async throws {
        // Given
        let mockTokenFactory = MockJWTTokenFactory()
        mockTokenFactory.setValidateTokenResponse(true)
        
        // When
        let isValid = await mockTokenFactory.validateJWTString(token: "test-token")
        
        // Then
        #expect(isValid == true)
        
        let calls = mockTokenFactory.getCallRecords()
        #expect(calls.count == 1)
        #expect(calls[0].action == .validateJWTString("test-token"))
    }
    
    @Test("Token factory validates invalid JWT token")
    func testTokenFactoryValidatesInvalidToken() async throws {
        // Given
        let mockTokenFactory = MockJWTTokenFactory()
        mockTokenFactory.setValidateTokenResponse(false)
        
        // When
        let isValid = await mockTokenFactory.validateJWTString(token: "invalid-token")
        
        // Then
        #expect(isValid == false)
        
        let calls = mockTokenFactory.getCallRecords()
        #expect(calls.count == 1)
        #expect(calls[0].action == .validateJWTString("invalid-token"))
    }
    
    @Test("Token factory call records work correctly")
    func testTokenFactoryCallRecords() async throws {
        // Given
        let mockTokenFactory = MockJWTTokenFactory()
        mockTokenFactory.setGenerateTokenResponse("token1")
        mockTokenFactory.setValidateTokenResponse(true)
        mockTokenFactory.setGenerateTokenResponse("token2") // Add second response
        
        // When
        _ = try await mockTokenFactory.generateJWTString()
        _ = await mockTokenFactory.validateJWTString(token: "token1")
        _ = try await mockTokenFactory.generateJWTString()
        
        // Then
        let calls = mockTokenFactory.getCallRecords()
        #expect(calls.count == 3)
        #expect(calls[0].action == .generateJWTString)
        #expect(calls[1].action == .validateJWTString("token1"))
        #expect(calls[2].action == .generateJWTString)
    }
}