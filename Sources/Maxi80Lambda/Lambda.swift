import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation

import Maxi80Backend

@main
// use actor to ensure thread safe access to authTokenString
actor Maxi80Lambda: LambdaHandler {

    private var authTokenString: String? = nil

    private let token = Token(secretKey: Secrets.privateKey.rawValue, keyId: Secrets.keyId.rawValue, issuerId: Secrets.teamId.rawValue)

    private let httpClient = HTTPClient()

    init(context: LambdaInitializationContext) async throws {
        context.logger.info(
            "Log Level env var : \(ProcessInfo.processInfo.environment["LOG_LEVEL"] ?? "undefined" )")
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
                        return APIGatewayV2Response(statusCode: .badRequest, headers: header, body: "no 'term' query paramater")
                    }
                    response = try await search(for: term, context) 
            }

            return APIGatewayV2Response(statusCode: .ok, headers: header, body: String(data: response, encoding: .utf8))

        } catch {
            header["content-type"] = "text/plain"
            return APIGatewayV2Response(statusCode: .internalServerError, headers: header, body: "\(error.localizedDescription)")
        }
    }

    func station() -> Station {
        return Station.default
    }

    func search(for: String, _ context: AWSLambdaRuntimeCore.LambdaContext) async throws -> Data {

        // generate a new auth token if we have one that has expired 
        // this is thread-safe because this struct is an actor 
        if !(await self.token.validate(token: authTokenString)) {
            context.logger.debug("No Apple Music Auth Token or it is expired, generating a new one")
            authTokenString = try? await token.generate()
        } else {
            context.logger.debug("Re-using a valid Apple Music Auth Token")
        }

        guard let token = authTokenString else {
            throw LambdaError.noAuthenticationToken(msg: "Search: can not generate an authentication token")
        }

        let (data, _) = try await httpClient.apiCall(url: AppleMusicEndpoint.test.url(),
                                                           headers: ["Authorization" : "Bearer \(token)"])
        return data

    }

    func encode<T: Encodable>(_ data: T) throws -> Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(data)
    }
}
