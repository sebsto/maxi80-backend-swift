import Foundation
import AWSSecretsManager

public struct SecretsManager {

  let secretName: String 
  let region: String 

  func getSecret() async throws -> Secret {
    // Configure Secrets Manager client
    guard let client = try? SecretsManagerClient(region: region) else {
      throw SecretsManagerError.cannotCreateClient(reason: "Failed to create SecretsManager client")
    }
    
    // Create GetSecretValue request
    let request = GetSecretValueInput(secretId: secretName)
    
    // Get the secret value
    guard let response = try? await client.getSecretValue(input: request) else {
      throw SecretsManagerError.invalidResponse(reason: "Error calling SecretsManager client")
    }
    
    // Decode JSON data
    guard let secret = response.secretString?.data(using: .utf8) else {
      throw SecretsManagerError.decodingFailed(reason: "Failed to decode secret value")
    }
    
    let decoder = JSONDecoder()
    let decodedData = try decoder.decode(Secret.self, from: secret)
    
    return decodedData
  }  

  public func storeSecret(secret: Secret) async throws -> String {
    guard let client = try? SecretsManagerClient(region: region) else {
      throw SecretsManagerError.cannotCreateClient(reason: "Failed to create SecretsManager client")
    }

    let encoder = JSONEncoder() 
    let data = try encoder.encode(secret)
    let secretString = String(data: data, encoding: .utf8)!
    
    var result: String = "no arn returned"
    do {

      let request = CreateSecretInput(name: secretName, secretString: secretString)
      let response = try await client.createSecret(input: request) 
      if let arn = response.arn {
        result = arn
      }

    } catch is ResourceExistsException {

      let request = UpdateSecretInput(secretId: secretName, secretString: secretString)
      let response = try await client.updateSecret(input: request) 
      if let arn = response.arn {
        result = arn
      }

    } catch {
      print(error)
    }

    return result
  }  
}

// Define Secrets Manager error enum for clarity
enum SecretsManagerError: Error {
  case decodingFailed(reason: String)
  case cannotCreateClient(reason: String)
  case invalidResponse(reason: String)
}

public struct Secret: Codable {
  public init(privateKey: String, teamId: String, keyId: String) {
    self.privateKey = privateKey
    self.teamId = teamId
    self.keyId = keyId
  }
  public let privateKey: String
  public let teamId: String
  public let keyId: String
}
