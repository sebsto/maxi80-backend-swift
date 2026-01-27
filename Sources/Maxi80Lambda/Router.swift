import AWSLambdaEvents
import HTTPTypes
import Logging
import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Router handles request routing and returns the appropriate action
public struct Router {
    private let actions: [any Action]
    private let logger: Logger

    public init(actions: [any Action], logger: Logger) {
        self.actions = actions
        self.logger = logger
    }

    /// Routes an incoming API Gateway request to the appropriate action
    public func route(_ event: APIGatewayRequest) -> Result<any Action, RouterError> {
        logger.trace("Routing request - Method: \(event.httpMethod.rawValue), Path: \(event.path)")

        // Verify path exists
        guard let endpoint = Maxi80Endpoint.from(path: event.path) else {
            return .failure(.pathNotFound(path: event.path))
        }

        // Find action matching both endpoint and method
        guard let action = actions.first(where: { $0.endpoint == endpoint && $0.method == event.httpMethod }) else {
            return .failure(.methodNotAllowed(path: event.path, method: event.httpMethod.rawValue))
        }

        return .success(action)
    }
}

/// Router-specific errors
public enum RouterError: Error, CustomStringConvertible {
    case pathNotFound(path: String)
    case methodNotAllowed(path: String, method: String)

    public var description: String {
        switch self {
        case .pathNotFound(let path):
            return "Path not found: \(path)"
        case .methodNotAllowed(let path, let method):
            return "Method \(method) not allowed for path: \(path)"
        }
    }

    public var statusCode: HTTPResponse.Status {
        switch self {
        case .pathNotFound:
            return .notFound
        case .methodNotAllowed:
            return .methodNotAllowed
        }
    }
}
