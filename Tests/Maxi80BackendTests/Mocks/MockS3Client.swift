@testable import Maxi80Lambda

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Mock S3 client for testing
public actor MockS3Client: S3ClientProtocol {

    private var existsResults: [Bool] = []
    private var presignedURLs: [String] = []
    private var errors: [Error] = []
    private var callRecords: [(bucket: String, key: String)] = []
    private var presignExpirations: [TimeInterval] = []
    private var existsIndex = 0
    private var presignIndex = 0

    public init() {}

    public func objectExists(bucket: String, key: String) async throws -> Bool {
        callRecords.append((bucket: bucket, key: key))

        if existsIndex < errors.count {
            let error = errors[existsIndex]
            existsIndex += 1
            throw error
        }

        guard existsIndex < existsResults.count else {
            return false
        }

        let result = existsResults[existsIndex]
        existsIndex += 1
        return result
    }

    public func presignedGetURL(bucket: String, key: String, expiration: TimeInterval) async throws -> String {
        presignExpirations.append(expiration)

        guard presignIndex < presignedURLs.count else {
            return "https://s3.example.com/\(key)"
        }

        let result = presignedURLs[presignIndex]
        presignIndex += 1
        return result
    }

    // MARK: - Test helpers

    public func setExists(_ exists: Bool) {
        existsResults.append(exists)
    }

    public func setPresignedURL(_ url: String) {
        presignedURLs.append(url)
    }

    public func setError(_ error: Error) {
        errors.append(error)
    }

    public func getCallRecords() -> [(bucket: String, key: String)] {
        callRecords
    }

    public func getPresignExpirations() -> [TimeInterval] {
        presignExpirations
    }

    public func reset() {
        existsResults.removeAll()
        presignedURLs.removeAll()
        errors.removeAll()
        callRecords.removeAll()
        presignExpirations.removeAll()
        existsIndex = 0
        presignIndex = 0
    }
}
