import AWSLambdaEvents
import AWSLambdaRuntime
import Foundation
import Logging

/// Shared test helpers for creating test objects
enum TestHelpers {

    /// Creates an APIGatewayRequest using JSON decoding to avoid initialization issues
    static func createAPIGatewayRequest(
        path: String,
        httpMethod: String = "GET",
        queryStringParameters: [String: String]? = nil
    ) throws -> APIGatewayRequest {

        let queryParamsJson: String
        if let queryParams = queryStringParameters, !queryParams.isEmpty {
            let data = try JSONEncoder().encode(queryParams)
            queryParamsJson = String(data: data, encoding: .utf8)!
        } else {
            queryParamsJson = "null"
        }

        let json = """
            {
                "resource": "/{proxy+}",
                "path": "\(path)",
                "httpMethod": "\(httpMethod)",
                "headers": {
                    "Accept": "application/json"
                },
                "multiValueHeaders": {
                    "Accept": ["application/json"]
                },
                "queryStringParameters": \(queryParamsJson),
                "multiValueQueryStringParameters": null,
                "pathParameters": {
                    "proxy": "\(path.dropFirst())"
                },
                "stageVariables": null,
                "requestContext": {
                    "accountId": "123456789",
                    "apiId": "test-api",
                    "domainName": "test.execute-api.us-east-1.amazonaws.com",
                    "domainPrefix": "test",
                    "extendedRequestId": "test-request-id",
                    "httpMethod": "\(httpMethod)",
                    "identity": {
                        "accessKey": null,
                        "accountId": null,
                        "apiKey": null,
                        "apiKeyId": null,
                        "caller": null,
                        "cognitoAuthenticationProvider": null,
                        "cognitoAuthenticationType": null,
                        "cognitoIdentityId": null,
                        "cognitoIdentityPoolId": null,
                        "principalOrgId": null,
                        "sourceIp": "127.0.0.1",
                        "user": null,
                        "userAgent": "test-agent",
                        "userArn": null
                    },
                    "path": "/Prod\(path)",
                    "protocol": "HTTP/1.1",
                    "requestId": "test-request-id",
                    "requestTime": "09/Apr/2015:12:34:56 +0000",
                    "requestTimeEpoch": 1428582896000,
                    "resourceId": "123456",
                    "resourcePath": "/{proxy+}",
                    "stage": "Prod"
                },
                "body": null,
                "isBase64Encoded": false
            }
            """

        let data = json.data(using: .utf8)!
        return try JSONDecoder().decode(APIGatewayRequest.self, from: data)
    }
}
