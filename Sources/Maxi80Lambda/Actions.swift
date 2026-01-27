import AWSLambdaEvents
import HTTPTypes
import Logging
import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Protocol for all action handlers
public protocol Action {
    /// The endpoint path this action handles
    var endpoint: Maxi80Endpoint { get }

    /// The HTTP method this action handles
    var method: HTTPRequest.Method { get }

    /// Handle the request
    func handle(event: APIGatewayRequest) async throws -> Data
}

/// Handles station information requests
public struct StationAction: Action {
    public let endpoint: Maxi80Endpoint = .station
    public let method: HTTPRequest.Method = .get
    private let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

    public func handle(event: APIGatewayRequest) async throws -> Data {
        logger.debug("Handling station request")
        let station = Station.default
        return try encode(station)
    }

    private func encode<T: Encodable>(_ data: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(data)
    }
}

/// Handles Apple Music search requests
public struct SearchAction: Action {
    public let endpoint: Maxi80Endpoint = .search
    public let method: HTTPRequest.Method = .get
    private let httpClient: any HTTPClientProtocol
    private let authProvider: any AuthorizationProvider
    private let logger: Logger

    public init(
        httpClient: any HTTPClientProtocol,
        authProvider: any AuthorizationProvider,
        logger: Logger
    ) {
        self.httpClient = httpClient
        self.authProvider = authProvider
        self.logger = logger
    }

    public func handle(event: APIGatewayRequest) async throws -> Data {
        logger.debug("Handling search request")

        // Extract required search term
        guard let term = event.queryStringParameters["term"] else {
            throw ActionError.missingParameter(name: "term")
        }

        return try await search(for: term)
    }

    private func search(for term: String) async throws -> Data {
        let searchFields = AppleMusicSearchType.items(searchTypes: [.songs])
        let searchTerms = AppleMusicSearchType.term(search: term)

        let (data, _) = try await httpClient.apiCall(
            url: AppleMusicEndpoint.search.url(args: [searchFields, searchTerms]),
            method: .GET,
            body: nil,
            headers: try await authProvider.authorizationHeader(),
            timeout: 10
        )

        return data
    }
}

/// Action-specific errors
public enum ActionError: Error, CustomStringConvertible {
    case missingParameter(name: String)
    case invalidParameter(name: String, reason: String)

    public var description: String {
        switch self {
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameter(let name, let reason):
            return "Invalid parameter '\(name)': \(reason)"
        }
    }
}

/// Protocol for providing authorization headers
public protocol AuthorizationProvider {
    func authorizationHeader() async throws -> [String: String]
}
