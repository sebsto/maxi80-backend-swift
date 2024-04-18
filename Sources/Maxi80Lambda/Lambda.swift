import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation

import ClientRuntime

import Maxi80Backend

@main
struct Maxi80Lambda: LambdaHandler {

    // isolate the shared mutable state as an actor
    // this is required for Swift 6, but not for Lambda
    // as each Lambda container is called once at a time
    actor JWTCache {
        var authTokenString: String? = nil
        func token(_ token: String) async {
            self.authTokenString = token
        }
        func token() async -> String? {
            return self.authTokenString
        }
    }
    
    private let tokenFactory: TokenFactory?
    private let tokenCache: JWTCache = JWTCache()

    private let httpClient = HTTPClient()

    let secretName = "Maxi80_AppleMusicAPI"

    init(context: LambdaInitializationContext) async throws {
        let logLevel = ProcessInfo.processInfo.environment["LOG_LEVEL"] ?? "undefined"
        context.logger.info("Log Level env var : \(logLevel)")
        if logLevel == "debug" || logLevel == "trace" {
            await SDKLoggingSystem.initialize(logLevel: .debug)
        } else {
            await SDKLoggingSystem.initialize(logLevel: .warning)
        }

        // read the region from the environment variable
        guard let region = ProcessInfo.processInfo.environment["AWS_REGION"] else {
            context.logger.error("Can not read the AWS_Region environment variable")
            tokenFactory = nil
            return
        }

        let secretsManager = SecretsManager(secretName: secretName, region: region)
        guard let secret = try? await secretsManager.getSecret() else {
            context.logger.error("Can not read the \(secretName) secret in region: \(region)")
            tokenFactory = nil
            return
        }
        tokenFactory = TokenFactory(secretKey: secret.privateKey,
                                    keyId: secret.keyId,
                                    issuerId: secret.teamId)
    }

    // the return value must be either APIGatewayV2Response or any Encodable struct
    func handle(_ event: APIGatewayV2Request, context: AWSLambdaRuntimeCore.LambdaContext) async throws -> APIGatewayV2Response {
        var header = HTTPHeaders()
        do {
            context.logger.debug("HTTP API Message received")
            context.logger.debug("Method: \(event.context.http.method.rawValue)")
            context.logger.debug("Path: \(event.rawPath)")

            header["content-type"] = "application/json"

            // verify the action is a GET, the only one we accept
            guard event.context.http.method == HTTPMethod.GET else {
                return APIGatewayV2Response(statusCode: .notFound, headers: header, body: "Only GET methods are accepted")
            }

            // verify the path is a well known one (as defined in the Endpoint enum)
            guard let path = Endpoint.from(path: event.rawPath) else {
                return APIGatewayV2Response(statusCode: .notFound, headers: header, body: "unknown path: \(event.rawPath)")
            }

            // route the request based on path 
            var response: Data
            switch path {
                case .station:
                    response = try encode(station())
                case .search: 
                    guard let term = event.queryStringParameters?["term"] else {
                        return APIGatewayV2Response(statusCode: .badRequest,
                                                    headers: header,
                                                    body: "no 'term' query paramater")
                    }
                    response = try await search(for: term, context) 
            }

            return APIGatewayV2Response(statusCode: .ok,
                                        headers: header,
                                        body: String(data: response, encoding: .utf8))

        } catch {
            header["content-type"] = "text/plain"
            return APIGatewayV2Response(statusCode: .internalServerError, headers: header, body: "\(error.localizedDescription)")
        }
    }

    private func authorizationHeader(_ context: AWSLambdaRuntimeCore.LambdaContext) async throws -> [String:String] {

        guard let tokenFactory = self.tokenFactory else {
            throw LambdaError.noTokenFactory(msg: "TokenFactory has not been initialized. This is likely because we couldn't access SecretsManager to retrieve the signing keys")
        }

        // generate a new auth token if we have one that has expired 
        // this is thread-safe because this struct is an actor 
        var authTokenString = await self.tokenCache.token()
        if !(await tokenFactory.validate(token: authTokenString)) {
            context.logger.debug("No Apple Music Auth Token or it is expired, generating a new one")
            authTokenString = try? await tokenFactory.generate()
        } else {
            context.logger.debug("Re-using a valid Apple Music Auth Token")
        }

        guard let token = authTokenString else {
            throw LambdaError.noAuthenticationToken(msg: "Search: can not generate an authentication token")
        }
        await self.tokenCache.token(token)
        return ["Authorization" : "Bearer \(token)"]
    }

    func station() -> Station {
        return Station.default
    }

    func search(for term: String, _ context: AWSLambdaRuntimeCore.LambdaContext) async throws -> Data {

        let searchFields = AppleMusicSearchType.items(searchTypes: [.artists, .albums, .songs])
        let searchterms = AppleMusicSearchType.term(search: term)
        let (data, _) = try await httpClient.apiCall(
                                        url: AppleMusicEndpoint.search.url(args: [searchFields, searchterms]),
                                        headers: authorizationHeader(context)
                                  )
        return data

    }

    func encode<T: Encodable>(_ data: T) throws -> Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(data)
    }
}
