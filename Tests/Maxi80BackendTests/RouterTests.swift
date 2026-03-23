import AWSLambdaEvents
import Foundation
import HTTPTypes
import Logging
import Testing

@testable import Maxi80Backend
@testable import Maxi80Lambda

@Suite("Router and Actions Integration Tests")
struct RouterTests {

    // MARK: - Endpoint Tests

    @Test("Endpoint from path returns correct endpoint")
    func testEndpointFromPath() {
        // Valid paths
        #expect(Maxi80Endpoint.from(path: "/station") == .station)
        #expect(Maxi80Endpoint.from(path: "/artwork") == .artwork)

        // Invalid paths
        #expect(Maxi80Endpoint.from(path: "/invalid") == nil)
        #expect(Maxi80Endpoint.from(path: "/") == nil)
        #expect(Maxi80Endpoint.from(path: "") == nil)
    }

    @Test("Endpoint raw values are correct")
    func testEndpointRawValues() {
        #expect(Maxi80Endpoint.station.rawValue == "/station")
        #expect(Maxi80Endpoint.artwork.rawValue == "/artwork")
    }

    // MARK: - Action Tests

    @Test("StationAction has correct endpoint and method")
    func testStationActionProperties() {
        let logger = Logger(label: "test")
        let action = StationAction(logger: logger)

        #expect(action.endpoint == .station)
        #expect(action.method == .get)
    }

    @Test("ArtworkAction has correct endpoint and method")
    func testArtworkActionProperties() {
        let logger = Logger(label: "test")
        let mockS3Client = MockS3Client()

        let action = ArtworkAction(
            s3Client: mockS3Client,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )

        #expect(action.endpoint == .artwork)
        #expect(action.method == .get)
    }

    @Test("StationAction handles request correctly")
    func testStationActionHandle() async throws {
        let logger = Logger(label: "test")
        let action = StationAction(logger: logger)

        let event = try TestHelpers.createAPIGatewayRequest(path: "/station")
        let data = try await action.handle(event: event)

        // Decode the response
        let station = try JSONDecoder().decode(Station.self, from: data)
        #expect(station.name == "Maxi 80")
        #expect(station.streamUrl == "https://audio1.maxi80.com")
    }

    @Test("ArtworkAction throws error when artist parameter is missing")
    func testArtworkActionMissingArtist() async throws {
        let logger = Logger(label: "test")
        let mockS3Client = MockS3Client()

        let action = ArtworkAction(
            s3Client: mockS3Client,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )

        let event = try TestHelpers.createAPIGatewayRequest(path: "/artwork")

        await #expect(throws: ActionError.self) {
            _ = try await action.handle(event: event)
        }
    }

    @Test("ArtworkAction throws error when title parameter is missing")
    func testArtworkActionMissingTitle() async throws {
        let logger = Logger(label: "test")
        let mockS3Client = MockS3Client()

        let action = ArtworkAction(
            s3Client: mockS3Client,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )

        let event = try TestHelpers.createAPIGatewayRequest(
            path: "/artwork",
            queryStringParameters: ["artist": "Duran Duran"]
        )

        await #expect(throws: ActionError.self) {
            _ = try await action.handle(event: event)
        }
    }

    @Test("ArtworkAction returns presigned URL when artwork exists")
    func testArtworkActionExists() async throws {
        let logger = Logger(label: "test")
        let mockS3Client = MockS3Client()
        await mockS3Client.setExists(true)
        await mockS3Client.setPresignedURL("https://s3.example.com/v2/Duran%20Duran/Rio/artwork.jpg")

        let action = ArtworkAction(
            s3Client: mockS3Client,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )

        let event = try TestHelpers.createAPIGatewayRequest(
            path: "/artwork",
            queryStringParameters: ["artist": "Duran Duran", "title": "Rio"]
        )

        let data = try await action.handle(event: event)
        let response = try JSONDecoder().decode(ArtworkResponse.self, from: data)
        #expect(!response.url.isEmpty)
    }

    @Test("ArtworkAction returns empty data when artwork not found")
    func testArtworkActionNotFound() async throws {
        let logger = Logger(label: "test")
        let mockS3Client = MockS3Client()
        await mockS3Client.setExists(false)

        let action = ArtworkAction(
            s3Client: mockS3Client,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )

        let event = try TestHelpers.createAPIGatewayRequest(
            path: "/artwork",
            queryStringParameters: ["artist": "Unknown", "title": "Song"]
        )

        let data = try await action.handle(event: event)
        #expect(data.isEmpty)
    }

    // MARK: - Router Tests

    @Test("Router routes GET /station to StationAction")
    func testRouterStationEndpoint() throws {
        let logger = Logger(label: "test")
        let stationAction = StationAction(logger: logger)
        let router = Router(actions: [stationAction], logger: logger)

        let event = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "GET")
        let result = router.route(event)

        guard case .success(let action) = result else {
            Issue.record("Expected success but got failure")
            return
        }

        #expect(action.endpoint == .station)
        #expect(action.method == .get)
    }

    @Test("Router routes GET /artwork to ArtworkAction")
    func testRouterArtworkEndpoint() throws {
        let logger = Logger(label: "test")
        let mockS3Client = MockS3Client()

        let artworkAction = ArtworkAction(
            s3Client: mockS3Client,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )
        let router = Router(actions: [artworkAction], logger: logger)

        let event = try TestHelpers.createAPIGatewayRequest(path: "/artwork", httpMethod: "GET")
        let result = router.route(event)

        guard case .success(let action) = result else {
            Issue.record("Expected success but got failure")
            return
        }

        #expect(action.endpoint == .artwork)
        #expect(action.method == .get)
    }

    @Test("Router returns pathNotFound for invalid path")
    func testRouterInvalidPath() throws {
        let logger = Logger(label: "test")
        let router = Router(actions: [], logger: logger)

        let event = try TestHelpers.createAPIGatewayRequest(path: "/invalid", httpMethod: "GET")
        let result = router.route(event)

        guard case .failure(let error) = result else {
            Issue.record("Expected failure but got success")
            return
        }

        guard case .pathNotFound(let path) = error else {
            Issue.record("Expected pathNotFound error")
            return
        }

        #expect(path == "/invalid")
    }

    @Test("Router returns methodNotAllowed for unsupported HTTP method")
    func testRouterMethodNotAllowed() throws {
        let logger = Logger(label: "test")
        let stationAction = StationAction(logger: logger)
        let router = Router(actions: [stationAction], logger: logger)

        // StationAction only supports GET, try POST
        let event = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "POST")
        let result = router.route(event)

        guard case .failure(let error) = result else {
            Issue.record("Expected failure but got success")
            return
        }

        guard case .methodNotAllowed(let path, let method) = error else {
            Issue.record("Expected methodNotAllowed error")
            return
        }

        #expect(path == "/station")
        #expect(method == "POST")
    }

    @Test("Router handles multiple actions for same endpoint with different methods")
    func testRouterMultipleMethodsSameEndpoint() throws {
        let logger = Logger(label: "test")

        // Create GET action
        let getAction = StationAction(logger: logger)

        // Create a mock POST action for the same endpoint
        let postAction = MockPostStationAction(logger: logger)

        let router = Router(actions: [getAction, postAction], logger: logger)

        // Test GET
        let getEvent = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "GET")
        let getResult = router.route(getEvent)

        guard case .success(let getRoutedAction) = getResult else {
            Issue.record("Expected success for GET")
            return
        }
        #expect(getRoutedAction.method == .get)

        // Test POST
        let postEvent = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "POST")
        let postResult = router.route(postEvent)

        guard case .success(let postRoutedAction) = postResult else {
            Issue.record("Expected success for POST")
            return
        }
        #expect(postRoutedAction.method == .post)
    }

    @Test("Router error descriptions are correct")
    func testRouterErrorDescriptions() {
        let pathNotFoundError = RouterError.pathNotFound(path: "/test")
        #expect(pathNotFoundError.description == "Path not found: /test")
        #expect(pathNotFoundError.statusCode == .notFound)

        let methodNotAllowedError = RouterError.methodNotAllowed(path: "/test", method: "POST")
        #expect(methodNotAllowedError.description == "Method POST not allowed for path: /test")
        #expect(methodNotAllowedError.statusCode == .methodNotAllowed)
    }

    @Test("ActionError descriptions are correct")
    func testActionErrorDescriptions() {
        let missingParamError = ActionError.missingParameter(name: "term")
        #expect(missingParamError.description == "Missing required parameter: term")

        let invalidParamError = ActionError.invalidParameter(name: "limit", reason: "must be positive")
        #expect(invalidParamError.description == "Invalid parameter 'limit': must be positive")
    }

    // MARK: - Integration Tests

    @Test("End-to-end: Router routes request and action handles it")
    func testEndToEndRouting() async throws {
        let logger = Logger(label: "test")
        let stationAction = StationAction(logger: logger)
        let router = Router(actions: [stationAction], logger: logger)

        // Create request
        let event = try TestHelpers.createAPIGatewayRequest(path: "/station", httpMethod: "GET")

        // Route request
        let result = router.route(event)

        guard case .success(let action) = result else {
            Issue.record("Routing failed")
            return
        }

        // Handle request
        let data = try await action.handle(event: event)

        // Verify response
        let station = try JSONDecoder().decode(Station.self, from: data)
        #expect(station.name == "Maxi 80")
    }
}

// MARK: - Mock Helpers

/// Mock POST action for testing multiple methods on same endpoint
struct MockPostStationAction: Action {
    let endpoint: Maxi80Endpoint = .station
    let method: HTTPRequest.Method = .post
    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func handle(event: APIGatewayRequest) async throws -> Data {
        logger.debug("Handling POST station request")
        return Data()
    }
}
