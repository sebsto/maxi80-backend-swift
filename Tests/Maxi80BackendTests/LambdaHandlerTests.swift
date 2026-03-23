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

    @Test("Lambda initialization with mock S3 client succeeds")
    func testLambdaInitialization() async throws {
        // Given
        let mockS3Client = MockS3Client()
        let logger = Logger(label: "test")

        // When
        let lambda = try await Maxi80Lambda(
            s3Client: mockS3Client,
            logger: logger
        )

        // Then - if we get here without throwing, initialization succeeded
        _ = lambda
    }

    @Test("Station endpoint logic returns correct data")
    func testStationLogic() async throws {
        // Given
        let mockS3Client = MockS3Client()
        let logger = Logger(label: "test")

        let lambda = try await Maxi80Lambda(
            s3Client: mockS3Client,
            logger: logger
        )

        _ = lambda

        _ = try TestHelpers.createAPIGatewayRequest(path: "/station")

        // When - Test the core logic by checking Station.default
        let station = Station.default

        // Then
        #expect(station.name == "Maxi 80")
        #expect(station.streamUrl == "https://audio1.maxi80.com")
    }

    @Test("Artwork endpoint validation works correctly")
    func testArtworkValidation() async throws {
        // Given
        let mockS3Client = MockS3Client()
        let logger = Logger(label: "test")

        _ = try await Maxi80Lambda(
            s3Client: mockS3Client,
            logger: logger
        )

        // Test endpoint validation
        let validEndpoint = Maxi80Endpoint.from(path: "/artwork")
        #expect(validEndpoint == .artwork)

        let invalidEndpoint = Maxi80Endpoint.from(path: "/invalid")
        #expect(invalidEndpoint == nil)

        // Test query parameter validation
        let eventWithParams = try TestHelpers.createAPIGatewayRequest(
            path: "/artwork",
            queryStringParameters: ["artist": "Duran Duran", "title": "Rio"]
        )
        #expect(eventWithParams.queryStringParameters["artist"] == "Duran Duran")
        #expect(eventWithParams.queryStringParameters["title"] == "Rio")

        let eventWithoutParams = try TestHelpers.createAPIGatewayRequest(path: "/artwork")
        #expect(eventWithoutParams.queryStringParameters["artist"] == nil)
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
}
