import Logging
import Maxi80Backend

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
    let s3Client: S3ManagerProtocol
    let bucket: String
    let keyPrefix: String

    /// Checks if metadata.json already exists for this artist/title combination.
    func exists(artist: String, title: String) async throws -> Bool {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "metadata.json")
        return try await s3Client.objectExists(bucket: bucket, key: key)
    }

    func writeMetadata(_ metadata: CollectedMetadata, artist: String, title: String, logger: Logger) async throws {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "metadata.json")
        let data: Data
        do {
            data = try JSONEncoder().encode(metadata)
        } catch {
            throw CollectorError.s3WriteFailed(file: "metadata.json", reason: error.localizedDescription)
        }
        try await putObject(data: data, key: key, contentType: "application/json", file: "metadata.json", logger: logger)
    }

    func writeSearchResults(_ data: Data, artist: String, title: String, logger: Logger) async throws {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "search.json")
        try await putObject(data: data, key: key, contentType: "application/json", file: "search.json", logger: logger)
    }

    func writeArtwork(_ data: Data, artist: String, title: String, logger: Logger) async throws {
        let key = buildS3Key(prefix: keyPrefix, artist: artist, title: title, file: "artwork.jpg")
        try await putObject(data: data, key: key, contentType: "image/jpeg", file: "artwork.jpg", logger: logger)
    }

    private func putObject(data: Data, key: String, contentType: String, file: String, logger: Logger) async throws {
        logger.debug("Writing \(file) to s3://\(bucket)/\(key)")
        do {
            try await s3Client.putObject(data: data, bucket: bucket, key: key, contentType: contentType)
        } catch {
            logger.error("S3 PutObject failed for \(file): \(String(describing: error))")
            throw CollectorError.s3WriteFailed(file: file, reason: "\(error)")
        }
    }
}
