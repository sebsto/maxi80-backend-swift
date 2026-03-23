import AWSS3
import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Builds an S3 key from prefix, artist, title, and file name.
func buildS3Key(prefix: String, artist: String, title: String, file: String) -> String {
    "\(prefix)/\(artist)/\(title)/\(file)"
}

struct S3Writer {
    let s3Client: S3Client
    let bucket: String
    let keyPrefix: String
    let logger: Logger

    /// Checks if metadata.json already exists for this artist/title combination.
    func exists(artist: String, title: String) async throws -> Bool {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "metadata.json")
        do {
            _ = try await s3Client.headObject(input: HeadObjectInput(bucket: bucket, key: key))
            return true
        } catch is AWSS3.NotFound {
            return false
        } catch {
            // For HeadObject, a 404 may come as a different error type
            // Check if it's a "not found" type error
            return false
        }
    }

    func writeMetadata(_ metadata: CollectedMetadata, artist: String, title: String) async throws {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "metadata.json")
        let data: Data
        do {
            data = try JSONEncoder().encode(metadata)
        } catch {
            throw CollectorError.s3WriteFailed(file: "metadata.json", reason: error.localizedDescription)
        }
        try await putObject(data: data, key: key, contentType: "application/json", file: "metadata.json")
    }

    func writeSearchResults(_ data: Data, artist: String, title: String) async throws {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "search.json")
        try await putObject(data: data, key: key, contentType: "application/json", file: "search.json")
    }

    func writeArtwork(_ data: Data, artist: String, title: String) async throws {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "artwork.jpg")
        try await putObject(data: data, key: key, contentType: "image/jpeg", file: "artwork.jpg")
    }

    private func putObject(data: Data, key: String, contentType: String, file: String) async throws {
        logger.debug("Writing \(file) to s3://\(bucket)/\(key)")
        do {
            _ = try await s3Client.putObject(input: PutObjectInput(
                body: .data(data),
                bucket: bucket,
                contentType: contentType,
                key: key
            ))
        } catch {
            logger.error("S3 PutObject failed for \(file): \(String(describing: error))")
            throw CollectorError.s3WriteFailed(file: file, reason: "\(error)")
        }
    }
}
