import Testing
import Foundation
import Logging
import AWSLambdaEvents
import HTTPTypes
import NIOHTTP1
@testable import Maxi80Lambda
@testable import Maxi80Backend

@Suite("Error Handling Tests")
struct ErrorHandlingTests {
    
    @Test("HTTPClientError descriptions")
    func testHTTPClientErrorDescriptions() {
        // Given
        let badServerError = HTTPClientError.badServerResponse(status: .notFound)
        let zeroByteError = HTTPClientError.zeroByteResource
        
        // When
        let badServerDescription = String(describing: badServerError)
        let zeroByteDescription = String(describing: zeroByteError)
        
        // Then
        #expect(badServerDescription.contains("badServerResponse"))
        #expect(badServerDescription.contains("404")) // Check for status code instead of "notFound"
        #expect(zeroByteDescription.contains("zeroByteResource"))
    }
    
    @Test("MockError descriptions")
    func testMockErrorDescriptions() {
        // Given
        let noResponseError = MockError.noResponseConfigured
        let invalidTokenError = MockError.invalidToken
        
        // When
        let noResponseDescription = String(describing: noResponseError)
        let invalidTokenDescription = String(describing: invalidTokenError)
        
        // Then
        #expect(noResponseDescription.contains("noResponseConfigured"))
        #expect(invalidTokenDescription.contains("invalidToken"))
    }
    
    @Test("Mock HTTP client error handling")
    func testMockHTTPClientErrorHandling() async throws {
        // Given
        let mockHTTPClient = MockHTTPClient()
        mockHTTPClient.setError(HTTPClientError.badServerResponse(status: .internalServerError))
        
        // When & Then
        do {
            _ = try await mockHTTPClient.apiCall(
                url: URL(string: "https://api.music.apple.com/v1/catalog/fr/search")!,
                method: .GET,
                body: nil,
                headers: [:],
                timeout: 10
            )
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is HTTPClientError)
            let httpError = error as! HTTPClientError
            if case .badServerResponse(let status) = httpError {
                #expect(status == .internalServerError)
            } else {
                #expect(Bool(false), "Wrong error type")
            }
        }
    }
    
    @Test("Mock JWT token factory error handling")
    func testMockJWTTokenFactoryErrorHandling() async throws {
        // Given
        let mockTokenFactory = MockJWTTokenFactory()
        mockTokenFactory.setGenerateTokenError(MockError.invalidToken)
        
        // When & Then
        do {
            _ = try await mockTokenFactory.generateJWTString()
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            #expect(error is MockError)
            let mockError = error as! MockError
            #expect(mockError == .invalidToken)
        }
    }
}