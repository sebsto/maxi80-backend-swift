import AWSLambdaEvents
import Foundation
import Logging
import Testing

@testable import Maxi80Lambda

// MARK: - Helpers

/// Generates a random path string starting with `/` that is NOT `/station` or `/artwork`.
private func randomUnrecognizedPath() -> String {
    let knownPaths: Set<String> = ["/station", "/artwork"]
    let chars = "abcdefghijklmnopqrstuvwxyz0123456789-_"

    while true {
        let segmentCount = Int.random(in: 1...4)
        var path = ""
        for _ in 0..<segmentCount {
            let length = Int.random(in: 1...12)
            let segment = String((0..<length).map { _ in chars.randomElement()! })
            path += "/\(segment)"
        }
        if !knownPaths.contains(path) {
            return path
        }
    }
}

/// Returns a random HTTP method string that is NOT "GET".
private func randomNonGETMethod() -> String {
    let methods = ["POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"]
    return methods.randomElement()!
}

// MARK: - Property Tests

@Suite("Router Property Tests")
struct RouterPropertyTests {

    /// Creates a Router with both StationAction and ArtworkAction registered.
    private func makeRouter() -> Router {
        let logger = Logger(label: "test")
        let mockS3 = MockS3Client()
        let stationAction = StationAction(logger: logger)
        let artworkAction = ArtworkAction(
            s3Client: mockS3,
            bucket: "test-bucket",
            keyPrefix: "v2",
            urlExpiration: 3600,
            logger: logger
        )
        return Router(actions: [stationAction, artworkAction], logger: logger)
    }

    // Feature: replace-search-with-image-endpoint, Property 5: Unrecognized paths return path-not-found
    @Test("Property 5: Unrecognized paths return pathNotFound for random inputs")
    func unrecognizedPathsReturnPathNotFound() throws {
        // Validates: Requirements 5.4
        let router = makeRouter()
        let iterations = 100

        for _ in 0..<iterations {
            let path = randomUnrecognizedPath()
            let event = try TestHelpers.createAPIGatewayRequest(path: path, httpMethod: "GET")
            let result = router.route(event)

            guard case .failure(let error) = result else {
                Issue.record("Expected pathNotFound for path '\(path)' but got success")
                continue
            }

            guard case .pathNotFound(let returnedPath) = error else {
                Issue.record("Expected pathNotFound error for path '\(path)' but got \(error)")
                continue
            }

            #expect(returnedPath == path)
        }
    }

    // Feature: replace-search-with-image-endpoint, Property 6: Unsupported methods return method-not-allowed
    @Test("Property 6: Non-GET methods on known paths return methodNotAllowed for random inputs")
    func unsupportedMethodsReturnMethodNotAllowed() throws {
        // Validates: Requirements 5.5
        let router = makeRouter()
        let knownPaths = ["/station", "/artwork"]
        let iterations = 100

        for _ in 0..<iterations {
            let path = knownPaths.randomElement()!
            let method = randomNonGETMethod()
            let event = try TestHelpers.createAPIGatewayRequest(path: path, httpMethod: method)
            let result = router.route(event)

            guard case .failure(let error) = result else {
                Issue.record("Expected methodNotAllowed for \(method) \(path) but got success")
                continue
            }

            guard case .methodNotAllowed(let returnedPath, let returnedMethod) = error else {
                Issue.record("Expected methodNotAllowed error for \(method) \(path) but got \(error)")
                continue
            }

            #expect(returnedPath == path)
            #expect(returnedMethod == method)
        }
    }
}
