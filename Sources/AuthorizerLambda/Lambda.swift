import AWSLambdaEvents
import AWSLambdaRuntime
import Logging
import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A simple Lambda authorizer that validates an API key from the Authorization header.
/// The expected API key is read from SSM Parameter Store (SecureString) at cold start.
@main
struct AuthorizerLambda: LambdaHandler {

    private let expectedAPIKey: String

    init() async throws {
        let logger = Logger(label: "AuthorizerLambda")
        let parameterName = Lambda.env("API_KEY_PARAMETER") ?? "/maxi80/api-key"
        let region = Lambda.env("AWS_REGION").flatMap { Region(awsRegionName: $0) } ?? .eucentral1

        let parameterStore = try ParameterStoreManager<String>(region: region, logger: logger)
        self.expectedAPIKey = try await parameterStore.getSecret(parameterName: parameterName)

        logger.info("Authorizer initialized")
    }

    func handle(
        _ request: APIGatewayLambdaAuthorizerRequest,
        context: LambdaContext
    ) async throws -> APIGatewayLambdaAuthorizerSimpleResponse {

        context.logger.debug("Authorizer invoked")

        // Extract the API key from the Authorization header
        let authHeader = request.headers["authorization"] ?? request.headers["Authorization"]

        let isAuthorized: Bool
        if let authHeader, !expectedAPIKey.isEmpty {
            // Support both "Bearer <key>" and raw key formats
            let key = authHeader.hasPrefix("Bearer ")
                ? String(authHeader.dropFirst(7))
                : authHeader
            isAuthorized = key == expectedAPIKey
        } else {
            isAuthorized = false
        }

        if !isAuthorized {
            context.logger.warning("Unauthorized request")
        }

        return APIGatewayLambdaAuthorizerSimpleResponse(isAuthorized: isAuthorized, context: nil)
    }

    static func main() async throws {
        let handler = try await AuthorizerLambda()
        let runtime = LambdaRuntime(lambdaHandler: handler)
        try await runtime.run()
    }
}
