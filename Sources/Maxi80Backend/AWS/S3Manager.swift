@preconcurrency import AWSS3
import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// MARK: - S3 Client Protocol

/// Protocol abstracting S3 operations, enabling testability via mocks.
public protocol S3ManagerProtocol: Sendable {
    /// Check if an object exists at the given bucket/key.
    /// Returns true if exists, false if not found.
    /// Throws for unexpected S3 errors.
    func objectExists(bucket: String, key: String) async throws -> Bool

    /// Generate a pre-signed GetObject URL for the given bucket/key with the specified expiration.
    func presignedGetURL(bucket: String, key: String, expiration: TimeInterval) async throws -> URL

    /// Upload data to S3 at the given bucket/key with the specified content type.
    func putObject(data: Data, bucket: String, key: String, contentType: String) async throws

    /// Download an object from S3. Returns nil if the key does not exist (NoSuchKey).
    func getObject(bucket: String, key: String) async throws -> Data?
}

// MARK: - AWS S3 Client Adapter

/// Concrete implementation wrapping `AWSS3.S3Client`.
///
/// Safety invariant for `@unchecked Sendable`: This struct holds an `S3Client` instance which
/// is not yet annotated as `Sendable` by the AWS SDK for Swift. The `S3Client` is internally
/// thread-safe (it uses its own connection pool and serialization). The `Region` stored property
/// is a value type and immutable after initialization.
// TODO: Remove `@unchecked Sendable` once the AWS SDK for Swift marks `S3Client` as `Sendable`
public struct S3Manager: S3ManagerProtocol, @unchecked Sendable {
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

    public func presignedGetURL(bucket: String, key: String, expiration: TimeInterval) async throws -> URL {
        let input = GetObjectInput(bucket: bucket, key: key)
        let config = try await S3Client.S3ClientConfig(region: region.rawValue)
        guard let url = try await input.presignURL(config: config, expiration: expiration) else {
            throw S3ManagerError.presignFailed(key: key)
        }
        return url
    }

    public func putObject(data: Data, bucket: String, key: String, contentType: String) async throws {
        _ = try await s3Client.putObject(input: PutObjectInput(
            body: .data(data),
            bucket: bucket,
            contentType: contentType,
            key: key
        ))
    }

    public func getObject(bucket: String, key: String) async throws -> Data? {
        do {
            let output = try await s3Client.getObject(input: GetObjectInput(bucket: bucket, key: key))
            guard let body = output.body,
                  let data = try await body.readData() else {
                return nil
            }
            return data
        } catch is AWSS3.NoSuchKey {
            return nil
        }
    }
}

/// Errors specific to the S3 manager.
public enum S3ManagerError: Error {
    case presignFailed(key: String)
}
