import AWSSDKIdentity
import AWSSecretsManager
import Logging

// import SmithyIdentity

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct SecretsManager<S: Codable> {

    private let smClient: SecretsManagerClient
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let region: Region

    private let logger: Logger

    public init(region: Region, awsProfileName: String? = nil, logger: Logger) throws {

        var logger = logger
        logger[metadataKey: "Component"] = "SecretsManager"
        self.logger = logger

        // create a SecretsManager configuration
        self.region = region
        guard
            let config = try? SecretsManagerClient.SecretsManagerClientConfiguration(
                region: region.rawValue
            )
        else {
            throw SecretsManagerError.cannotCreateClient(
                reason: "Failed to create SecretsManager configuration"
            )
        }
        logger.trace("Using region: \(region)")

        if let awsProfileName {
            logger.trace("Using credentials from AWS profile: \(awsProfileName)")
            config.awsCredentialIdentityResolver = ProfileAWSCredentialIdentityResolver(
                profileName: awsProfileName
            )
        }

        // Configure Secrets Manager client
        self.smClient = SecretsManagerClient(config: config)
    }

    public func getSecret(secretName: String) async throws -> S {

        // Create GetSecretValue request
        let request = GetSecretValueInput(secretId: secretName)

        // Get the secret value
        logger.trace("Retrieving secret: \(secretName)")
        guard let response = try? await self.smClient.getSecretValue(input: request) else {
            throw SecretsManagerError.invalidResponse(
                reason: """
                    Error calling SecretsManager client. Verify the following:
                    1/ the secret \(secretName) exists in \(region) 
                    2/ the calling code has secretsmanager:GetSecretValue IAM permission.
                    """
            )
        }
        logger.trace("Secret retrieved")

        // Decode JSON data
        guard let secret = response.secretString?.data(using: .utf8) else {
            throw SecretsManagerError.decodingFailed(reason: "Failed to decode secret value")
        }

        let decodedData = try decoder.decode(S.self, from: secret)

        logger.trace("Secret decoded")
        return decodedData
    }

    public func storeSecret(secret: S, secretName: String) async throws -> String {
        let data = try encoder.encode(secret)
        let secretString = String(data: data, encoding: .utf8)!

        let result: String
        do {

            logger.trace("Storing secret: \(secretName)")
            let request = CreateSecretInput(name: secretName, secretString: secretString)
            let response = try await self.smClient.createSecret(input: request)
            guard let arn = response.arn else {
                throw SecretsManagerError.invalidResponse(reason: "Response doesn't include an Arn")
            }
            logger.trace("Secret stored")
            result = arn

        } catch is ResourceExistsException {

            logger.trace("Storing secret generated an error, attempting to update it instead")
            let request = UpdateSecretInput(secretId: secretName, secretString: secretString)
            let response = try await self.smClient.updateSecret(input: request)
            guard let arn = response.arn else {
                throw SecretsManagerError.invalidResponse(reason: "Response doesn't include an Arn")
            }
            logger.trace("Secret updated")
            result = arn

        } catch {
            logger.error("Can not store nor update secret")
            throw SecretsManagerError.backendError(rootcause: error)
        }

        return result
    }
}

// Define Secrets Manager error enum for clarity
enum SecretsManagerError: Error {
    case decodingFailed(reason: String)
    case cannotCreateClient(reason: String)
    case invalidResponse(reason: String)
    case backendError(rootcause: Error)
}
