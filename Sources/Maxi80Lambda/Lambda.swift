import AWSLambdaEvents
import AWSLambdaRuntime
import HTTPTypes
import Logging
import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@main
struct Maxi80Lambda: LambdaHandler {

    private let router: Router
    private let logger: Logger

    // isolate the shared mutable state as an actor
    // in theory, we don't need this on Lambda as exactly one handler is running at a time

    init(
        musicAPIClient: HTTPClientProtocol? = nil,
        tokenFactory: JWTTokenFactoryProtocol? = nil,
        logger: Logger? = nil
    ) async throws {

        // read the LOG_LEVEL and configure the logger
        var logger = logger ?? Logger(label: "Maxi80Lambda")
        logger.logLevel = Lambda.env("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ?? .error
        logger.trace("Log level env var : \(logger.logLevel)")
        self.logger = logger

        // read the region from the environment variable
        let region = Lambda.env("AWS_REGION").flatMap { Region(awsRegionName: $0) } ?? .eucentral1
        self.logger.trace("Region: \(region)")

        let httpClient = musicAPIClient ?? MusicAPIClient(logger: self.logger)

        let resolvedTokenFactory: JWTTokenFactoryProtocol
        if let providedFactory = tokenFactory {
            resolvedTokenFactory = providedFactory
        } else {
            do {
                let secretName = Lambda.env("SECRETS") ?? "Maxi80-AppleMusicKey"
                let secretsManager = try SecretsManager<AppleMusicSecret>(region: region, logger: logger)
                let secret = try await secretsManager.getSecret(secretName: secretName)

                resolvedTokenFactory = JWTTokenFactory(
                    secretKey: secret.privateKey,
                    keyId: secret.keyId,
                    issuerId: secret.teamId
                )
            } catch {
                logger.error("Can't read AppleMusic API key secret. Root cause: \(error)")
                throw LambdaError.cantAccessMusicAPISecret(rootCause: error)
            }
        }

        // Initialize auth provider
        let authProvider = AppleMusicAuthProvider(
            tokenFactory: resolvedTokenFactory,
            logger: logger
        )

        // Initialize actions array
        let actions: [any Action] = [
            StationAction(logger: logger),
            SearchAction(
                httpClient: httpClient,
                authProvider: authProvider,
                logger: logger
            ),
        ]

        // Initialize router with actions
        self.router = Router(actions: actions, logger: logger)
    }

    // the return value must be either APIGatewayResponse or any Encodable struct
    func handle(_ event: APIGatewayRequest, context: LambdaContext) async throws -> APIGatewayResponse {
        var header = HTTPHeaders()
        header["content-type"] = "application/json"

        do {
            self.logger.trace("HTTP API Message received")

            // Route the request to get the action
            let action = try router.route(event).get()

            // Execute the action
            let responseData = try await action.handle(event: event)

            return APIGatewayResponse(
                statusCode: .ok,
                headers: header,
                body: String(data: responseData, encoding: .utf8)
            )

        } catch let error as RouterError {
            return APIGatewayResponse(
                statusCode: error.statusCode,
                headers: header,
                body: error.description
            )
        } catch let error as ActionError {
            return APIGatewayResponse(
                statusCode: .badRequest,
                headers: header,
                body: error.description
            )
        } catch {
            header["content-type"] = "text/plain"
            return APIGatewayResponse(
                statusCode: .internalServerError,
                headers: header,
                body: "\(error.localizedDescription)"
            )
        }
    }

    public static func main() async throws {
        let handler = try await Maxi80Lambda()
        let runtime = LambdaRuntime(lambdaHandler: handler)
        try await runtime.run()
    }
}

/// Provides Apple Music authorization headers with token caching
struct AppleMusicAuthProvider: AuthorizationProvider {
    private let tokenFactory: any JWTTokenFactoryProtocol
    private let tokenCache = TokenCache()
    private let logger: Logger

    // isolate the shared mutable state as an actor
    // in theory, we don't need this on Lambda as exactly one handler is running at a time
    actor TokenCache {
        var authTokenString: String? = nil
        func token(_ token: String) async {
            self.authTokenString = token
        }
        func token() async -> String? {
            self.authTokenString
        }
    }

    init(tokenFactory: any JWTTokenFactoryProtocol, logger: Logger) {
        self.tokenFactory = tokenFactory
        self.logger = logger
    }

    func authorizationHeader() async throws -> [String: String] {
        let token: String

        if let authToken = await self.tokenCache.token(),
            await tokenFactory.validateJWTString(token: authToken)
        {
            // reuse the auth token when we have one and it is still valid
            self.logger.debug("Re-using a valid Apple Music Auth Token")
            token = authToken
        } else {
            // generate a new auth token if we have none or one that has expired
            self.logger.debug("No Apple Music Auth Token or it is expired, generating a new one")
            token = try await self.tokenFactory.generateJWTString()
            await self.tokenCache.token(token)
        }
        return ["Authorization": "Bearer \(token)"]
    }
}
