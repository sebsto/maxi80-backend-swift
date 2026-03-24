import AWSLambdaEvents
@preconcurrency import AWSS3
import HTTPTypes
import Logging
import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Protocol for all action handlers
public protocol Action {
    /// The endpoint path this action handles
    var endpoint: Maxi80Endpoint { get }

    /// The HTTP method this action handles
    var method: HTTPRequest.Method { get }

    /// Handle the request
    func handle(event: APIGatewayRequest, logger: Logger) async throws -> Data
}

/// Handles station information requests
public struct StationAction: Action {
    public let endpoint: Maxi80Endpoint = .station
    public let method: HTTPRequest.Method = .get

    public init() {}

    public func handle(event: APIGatewayRequest, logger: Logger) async throws -> Data {
        logger.debug("Handling station request")
        let station = Station.default
        return try encode(station)
    }

    private func encode<T: Encodable>(_ data: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(data)
    }
}

/// Handles artwork lookup requests by checking S3 for artwork existence
/// and returning a pre-signed URL if found.
public struct ArtworkAction: Action {
    public let endpoint: Maxi80Endpoint = .artwork
    public let method: HTTPRequest.Method = .get

    private let s3Client: S3ClientProtocol
    private let bucket: String
    private let keyPrefix: String
    private let urlExpiration: TimeInterval

    public init(
        s3Client: S3ClientProtocol,
        bucket: String,
        keyPrefix: String,
        urlExpiration: TimeInterval
    ) {
        self.s3Client = s3Client
        self.bucket = bucket
        self.keyPrefix = keyPrefix
        self.urlExpiration = urlExpiration
    }

    public func handle(event: APIGatewayRequest, logger: Logger) async throws -> Data {
        logger.debug("Handling artwork request")

        guard let artist = event.queryStringParameters["artist"] else {
            throw ActionError.missingParameter(name: "artist")
        }
        guard let title = event.queryStringParameters["title"] else {
            throw ActionError.missingParameter(name: "title")
        }

        let key = "\(keyPrefix)/\(artist)/\(title)/artwork.jpg"

        let exists = try await s3Client.objectExists(bucket: bucket, key: key)
        guard exists else {
            return Data()
        }

        let url = try await s3Client.presignedGetURL(bucket: bucket, key: key, expiration: urlExpiration)
        let response = ArtworkResponse(url: url)
        return try JSONEncoder().encode(response)
    }
}

/// Action-specific errors
public enum ActionError: Error, CustomStringConvertible {
    case missingParameter(name: String)
    case invalidParameter(name: String, reason: String)

    public var description: String {
        switch self {
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .invalidParameter(let name, let reason):
            return "Invalid parameter '\(name)': \(reason)"
        }
    }
}

// MARK: - S3 Client Protocol

/// Protocol abstracting S3 operations for artwork lookup, enabling testability via mocks.
public protocol S3ClientProtocol: Sendable {
    /// Check if an object exists at the given bucket/key.
    /// Returns true if exists, false if not found.
    /// Throws for unexpected S3 errors.
    func objectExists(bucket: String, key: String) async throws -> Bool

    /// Generate a pre-signed GetObject URL for the given bucket/key with the specified expiration.
    func presignedGetURL(bucket: String, key: String, expiration: TimeInterval) async throws -> String
}

// MARK: - AWS S3 Client Adapter

/// Concrete implementation wrapping `AWSS3.S3Client` for HeadObject and pre-signed URL generation.
///
/// Safety invariant for `@unchecked Sendable`: This struct holds an `S3Client` instance which
/// is not yet annotated as `Sendable` by the AWS SDK for Swift. The `S3Client` is internally
/// thread-safe (it uses its own connection pool and serialization). The `Region` stored property
/// is a value type and immutable after initialization.
// TODO: Remove `@unchecked Sendable` once the AWS SDK for Swift marks `S3Client` as `Sendable`
public struct AWSS3ClientAdapter: S3ClientProtocol, @unchecked Sendable {
    private let s3Client: S3Client
    private let region: Region

    public init(s3Client: S3Client, region: Region) {
        self.s3Client = s3Client
        self.region = region
    }

    public func objectExists(bucket: String, key: String) async throws -> Bool {
        do {
            _ = try await s3Client.headObject(input: HeadObjectInput(bucket: bucket, key: key))
            return true
        } catch is AWSS3.NotFound {
            return false
        }
        // Other errors propagate as-is
    }

    public func presignedGetURL(bucket: String, key: String, expiration: TimeInterval) async throws -> String {
        let input = GetObjectInput(bucket: bucket, key: key)
        let config = try await S3Client.S3ClientConfig(region: region.rawValue)
        guard let url = try await input.presignURL(config: config, expiration: expiration) else {
            throw ActionError.invalidParameter(name: "key", reason: "Failed to generate pre-signed URL")
        }
        return url.absoluteString
    }
}

// MARK: - Artwork Response

/// JSON response model for the artwork endpoint.
public struct ArtworkResponse: Codable, Sendable {
    public let url: String

    public init(url: String) {
        self.url = url
    }
}
