import AWSLambdaEvents
import AWSLambdaRuntime
import AWSS3
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

    init(
        s3Client: S3ManagerProtocol? = nil,
        logger: Logger? = nil
    ) async throws {

        let logger = logger ?? LoggingConfiguration(logger: Logger(label: "Maxi80Lambda")).makeRuntimeLogger()
        logger.trace("Maxi80Lambda init started")

        // read the region from the environment variable
        let region = Lambda.env("AWS_REGION").flatMap { Region(awsRegionName: $0) } ?? .eucentral1
        logger.trace("Region: \(region)")

        // S3 configuration
        let bucket = Lambda.env("S3_BUCKET") ?? "artwork.maxi80.com"
        let keyPrefix = Lambda.env("KEY_PREFIX") ?? "v2"
        let urlExpiration = TimeInterval(Lambda.env("URL_EXPIRATION").flatMap { Int($0) } ?? 3600)

        let resolvedS3Client: S3ManagerProtocol
        if let provided = s3Client {
            resolvedS3Client = provided
        } else {
            let s3 = try S3Client(region: region.rawValue)
            resolvedS3Client = S3Manager(s3Client: s3, region: region)
        }

        // Initialize actions array
        let actions: [any Action] = [
            StationAction(),
            ArtworkAction(
                s3Client: resolvedS3Client,
                bucket: bucket,
                keyPrefix: keyPrefix,
                urlExpiration: urlExpiration
            ),
        ]

        // Initialize router with actions
        self.router = Router(actions: actions)
    }

    // the return value must be either APIGatewayResponse or any Encodable struct
    func handle(_ event: APIGatewayRequest, context: LambdaContext) async throws -> APIGatewayResponse {
        var header = HTTPHeaders()
        header["content-type"] = "application/json"

        do {
            context.logger.trace("HTTP API Message received")

            // Route the request to get the action
            let action = try router.route(event, logger: context.logger).get()
            context.logger.trace("Action identified: \(action)")
            
            // Execute the action
            let responseData = try await action.handle(event: event, logger: context.logger)

            if responseData.isEmpty {
                return APIGatewayResponse(statusCode: .noContent)
            } else {
                return APIGatewayResponse(
                    statusCode: .ok,
                    headers: header,
                    body: String(data: responseData, encoding: .utf8)
                )
            }

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
