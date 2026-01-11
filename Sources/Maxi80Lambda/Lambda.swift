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

    private let tokenFactory: JWTTokenFactoryProtocol
    private let httpClient: HTTPClientProtocol
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

        self.httpClient = musicAPIClient ?? MusicAPIClient(logger: self.logger)

        if let tokenFactory = tokenFactory {
            self.tokenFactory = tokenFactory
        } else {
            do {
                let secretName = Lambda.env("SECRETS") ?? "Maxi80-AppleMusicKey"
                let secretsManager = try SecretsManager<AppleMusicSecret>(region: region, logger: logger)
                let secret = try await secretsManager.getSecret(secretName: secretName)

                self.tokenFactory = JWTTokenFactory(
                    secretKey: secret.privateKey,
                    keyId: secret.keyId,
                    issuerId: secret.teamId
                )
            } catch {
                logger.error("Can't read AppleMusic API key secret. Root cause: \(error)")
                throw LambdaError.cantAccessMusicAPISecret(rootCause: error)
            }
        }
    }

    // the return value must be either APIGatewayResponse or any Encodable struct
    func handle(_ event: APIGatewayRequest, context: LambdaContext) async throws -> APIGatewayResponse {
        var header = HTTPHeaders()
        do {
            self.logger.trace("HTTP API Message received")
            self.logger.trace("Method: \(event.httpMethod.rawValue)")
            self.logger.trace("Path: \(event.path)")

            header["content-type"] = "application/json"

            // verify the action is a GET, the only one we accept
            guard event.httpMethod == .get else {
                return APIGatewayResponse(
                    statusCode: .notFound,
                    headers: header,
                    body: "Only GET methods are accepted"
                )
            }

            // verify the path is a well known one (as defined in the Endpoint enum)
            guard let path = Maxi80Endpoint.from(path: event.path) else {
                return APIGatewayResponse(
                    statusCode: .notFound,
                    headers: header,
                    body: "unknown path: \(event.path)"
                )
            }

            // route the request based on path
            var response: Data
            switch path {
            case .station:
                response = try encode(station())
            case .search:
                guard let term = event.queryStringParameters["term"] else {
                    return APIGatewayResponse(
                        statusCode: .badRequest,
                        headers: header,
                        body: "no 'term' query paramater"
                    )
                }
                response = try await search(for: term)
            }

            return APIGatewayResponse(
                statusCode: .ok,
                headers: header,
                body: String(data: response, encoding: .utf8)
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

    private func authorizationHeader() async throws -> [String: String] {

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

    private func station() -> Station {
        Station.default
    }

    private func search(for term: String) async throws -> Data {

        let searchFields = AppleMusicSearchType.items(searchTypes: [.artists, .albums, .songs])
        let searchterms = AppleMusicSearchType.term(search: term)
        let (data, _) = try await httpClient.apiCall(
            url: AppleMusicEndpoint.search.url(args: [searchFields, searchterms]),
            method: .GET,
            body: nil,
            headers: try await authorizationHeader(),
            timeout: 10
        )
        return data

    }

    private func encode<T: Encodable>(_ data: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(data)
    }

    public static func main() async throws {
        let handler = try await Maxi80Lambda()
        let runtime = LambdaRuntime(lambdaHandler: handler)
        try await runtime.run()
    }
}
