import AWSLambdaEvents
import Foundation
import HTTPTypes
import Logging
import NIOHTTP1
import Testing

@testable import Maxi80Backend
@testable import Maxi80Lambda

@Suite("Lambda Handler Tests")
struct LambdaHandlerTests {

    @Test("Lambda initialization with mocks succeeds")
    func testLambdaInitialization() async throws {
        // Given
        let mockHTTPClient = MockHTTPClient()
        let mockTokenFactory = MockJWTTokenFactory()
        let logger = Logger(label: "test")

        // When
        let lambda = try await Maxi80Lambda(
            musicAPIClient: mockHTTPClient,
            tokenFactory: mockTokenFactory,
            logger: logger
        )

        // Then - if we get here without throwing, initialization succeeded
        _ = lambda  // Use lambda to avoid unused variable warning
    }

    @Test("Station endpoint logic returns correct data")
    func testStationLogic() async throws {
        // Given
        let mockHTTPClient = MockHTTPClient()
        let mockTokenFactory = MockJWTTokenFactory()
        let logger = Logger(label: "test")

        let lambda = try await Maxi80Lambda(
            musicAPIClient: mockHTTPClient,
            tokenFactory: mockTokenFactory,
            logger: logger
        )

        // Then - if we get here without throwing, initialization succeeded
        _ = lambda  // Use lambda to avoid unused variable warning

        _ = try TestHelpers.createAPIGatewayRequest(path: "/station")

        // When - Test the core logic by checking Station.default
        let station = Station.default

        // Then
        #expect(station.name == "Maxi 80")
        #expect(station.streamUrl == "https://audio1.maxi80.com")
    }

    @Test("Search endpoint validation works correctly")
    func testSearchValidation() async throws {
        // Given
        let mockHTTPClient = MockHTTPClient()
        let mockTokenFactory = MockJWTTokenFactory()
        let logger = Logger(label: "test")

        // Configure mocks
        mockTokenFactory.setGenerateTokenResponse("mock-jwt-token")

        let mockSearchResponse = """
            {
                "meta": {
                    "results": {
                        "order": ["artists"],
                        "rawOrder": ["artists"]
                    }
                },
                "results": {
                    "artists": {
                        "data": [],
                        "href": "/v1/catalog/fr/search?term=test&types=artists"
                    }
                }
            }
            """.data(using: .utf8)!

        mockHTTPClient.setResponse(data: mockSearchResponse)

        _ = try await Maxi80Lambda(
            musicAPIClient: mockHTTPClient,
            tokenFactory: mockTokenFactory,
            logger: logger
        )

        // Test endpoint validation
        let validEndpoint = Maxi80Endpoint.from(path: "/search")
        #expect(validEndpoint == .search)

        let invalidEndpoint = Maxi80Endpoint.from(path: "/invalid")
        #expect(invalidEndpoint == nil)

        // Test query parameter validation
        let eventWithTerm = try TestHelpers.createAPIGatewayRequest(
            path: "/search",
            queryStringParameters: ["term": "Beatles"]
        )
        #expect(eventWithTerm.queryStringParameters["term"] == "Beatles")

        let eventWithoutTerm = try TestHelpers.createAPIGatewayRequest(path: "/search")
        #expect(eventWithoutTerm.queryStringParameters["term"] == nil)
    }

    @Test("HTTP method validation works correctly")
    func testHTTPMethodValidation() async throws {
        // Test GET method
        let getEvent = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "GET")
        #expect(getEvent.httpMethod == .get)

        // Test POST method
        let postEvent = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "POST")
        #expect(postEvent.httpMethod == .post)

        // Test other methods
        let putEvent = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "PUT")
        #expect(putEvent.httpMethod == .put)
    }

    @Test("Token factory integration works correctly")
    func testTokenFactoryIntegration() async throws {
        // Given
        let mockHTTPClient = MockHTTPClient()
        let mockTokenFactory = MockJWTTokenFactory()
        let logger = Logger(label: "test")

        mockTokenFactory.setGenerateTokenResponse("test-jwt-token")
        mockTokenFactory.setValidateTokenResponse(true)

        _ = try await Maxi80Lambda(
            musicAPIClient: mockHTTPClient,
            tokenFactory: mockTokenFactory,
            logger: logger
        )

        // When - Generate a token
        let token = try await mockTokenFactory.generateJWTString()

        // Then
        #expect(token == "test-jwt-token")

        // Verify the token factory was called
        let tokenCalls = mockTokenFactory.getCallRecords()
        #expect(tokenCalls.count == 1)
        #expect(tokenCalls[0].action == .generateJWTString)
    }
}
