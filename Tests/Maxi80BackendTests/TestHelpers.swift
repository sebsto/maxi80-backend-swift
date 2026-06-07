import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import Logging

/// Shared test helpers for creating test objects
enum TestHelpers {

    /// Creates an APIGatewayV2Request using JSON decoding to avoid initialization issues
    static func createAPIGatewayRequest(
        path: String,
        httpMethod: String = "GET",
        queryStringParameters: [String: String]? = nil
    ) throws -> APIGatewayV2Request {

        let queryParamsJson: String
        if let queryParams = queryStringParameters, !queryParams.isEmpty {
            let data = try JSONEncoder().encode(queryParams)
            queryParamsJson = String(data: data, encoding: .utf8)!
        } else {
            queryParamsJson = "{}"
        }

        let json = """
            {
                "version": "2.0",
                "routeKey": "ANY \(path)",
                "rawPath": "\(path)",
                "rawQueryString": "",
                "cookies": [],
                "headers": {
                    "accept": "application/json"
                },
                "queryStringParameters": \(queryParamsJson),
                "pathParameters": {},
                "stageVariables": {},
                "requestContext": {
                    "accountId": "123456789",
                    "apiId": "test-api",
                    "domainName": "test.execute-api.eu-central-1.amazonaws.com",
                    "domainPrefix": "test",
                    "stage": "$default",
                    "requestId": "test-request-id",
                    "http": {
                        "method": "\(httpMethod)",
                        "path": "\(path)",
                        "protocol": "HTTP/1.1",
                        "sourceIp": "127.0.0.1",
                        "userAgent": "test-agent"
                    },
                    "time": "09/Apr/2015:12:34:56 +0000",
                    "timeEpoch": 1428582896000
                },
                "body": null,
                "isBase64Encoded": false
            }
            """

        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(APIGatewayV2Request.self, from: data)
    }
}
