import Foundation
import AWSCognitoIdentity

// MARK: - Basic Usage with Permanent Credentials

func callAPIWithPermanentCredentials() async throws {
    let signer = SigV4Signer(
        accessKey: "YOUR_ACCESS_KEY",
        secretKey: "YOUR_SECRET_KEY",
        sessionToken: nil,
        region: "us-east-1"
    )
    
    var request = URLRequest(url: URL(string: "https://your-api-id.execute-api.us-east-1.amazonaws.com/prod/endpoint")!)
    request.httpMethod = "GET"
    
    let signedRequest = signer.sign(request: request)
    
    let (data, _) = try await URLSession.shared.data(for: signedRequest)
    print(String(data: data, encoding: .utf8) ?? "")
}

// MARK: - Usage with Cognito Identity Pool (Anonymous)

func callAPIWithCognitoAnonymous() async throws {
    let credentialsProvider = AWSCognitoCredentialsProvider(
        regionType: .USEast1,
        identityPoolId: "us-east-1:xxxx-xxxx-xxxx"
    )
    
    let credentials = await credentialsProvider.credentials()
    
    let signer = SigV4Signer(
        accessKey: credentials.accessKey,
        secretKey: credentials.secretKey,
        sessionToken: credentials.sessionToken,
        region: "us-east-1"
    )
    
    var request = URLRequest(url: URL(string: "https://your-api.execute-api.us-east-1.amazonaws.com/prod/search?term=test")!)
    request.httpMethod = "GET"
    
    let signedRequest = signer.sign(request: request)
    
    let (data, _) = try await URLSession.shared.data(for: signedRequest)
    print(String(data: data, encoding: .utf8) ?? "")
}

// MARK: - Usage with Cognito Identity Pool (Authenticated)

func callAPIWithCognitoAuthenticated(idToken: String) async throws {
    let credentialsProvider = AWSCognitoCredentialsProvider(
        regionType: .USEast1,
        identityPoolId: "us-east-1:xxxx-xxxx-xxxx"
    )
    
    // Add authenticated login
    credentialsProvider.logins = [
        AWSIdentityProviderApple: idToken
    ]
    
    let credentials = await credentialsProvider.credentials()
    
    let signer = SigV4Signer(
        accessKey: credentials.accessKey,
        secretKey: credentials.secretKey,
        sessionToken: credentials.sessionToken,
        region: "us-east-1"
    )
    
    var request = URLRequest(url: URL(string: "https://your-api.execute-api.us-east-1.amazonaws.com/prod/user/profile")!)
    request.httpMethod = "GET"
    
    let signedRequest = signer.sign(request: request)
    
    let (data, _) = try await URLSession.shared.data(for: signedRequest)
    print(String(data: data, encoding: .utf8) ?? "")
}

// MARK: - POST Request Example

func postDataToAPI(payload: [String: Any]) async throws {
    let credentialsProvider = AWSCognitoCredentialsProvider(
        regionType: .USEast1,
        identityPoolId: "us-east-1:xxxx-xxxx-xxxx"
    )
    
    let credentials = await credentialsProvider.credentials()
    
    let signer = SigV4Signer(
        accessKey: credentials.accessKey,
        secretKey: credentials.secretKey,
        sessionToken: credentials.sessionToken,
        region: "us-east-1"
    )
    
    var request = URLRequest(url: URL(string: "https://your-api.execute-api.us-east-1.amazonaws.com/prod/data")!)
    request.httpMethod = "POST"
    request.httpBody = try JSONSerialization.data(withJSONObject: payload)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let signedRequest = signer.sign(request: request)
    
    let (data, _) = try await URLSession.shared.data(for: signedRequest)
    print(String(data: data, encoding: .utf8) ?? "")
}
