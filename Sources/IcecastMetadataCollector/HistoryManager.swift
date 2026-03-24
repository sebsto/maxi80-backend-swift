import AWSS3
import Logging

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct HistoryEntry: Codable, Sendable, Equatable {
    let artist: String
    let title: String
    let artwork: String    // Full S3 key, e.g. "collected/ArtistName/SongTitle/artwork.jpg"
    let timestamp: String  // ISO 8601 UTC, e.g. "2025-01-15T14:30:00Z"
}

struct HistoryFile: Codable, Sendable, Equatable {
    var entries: [HistoryEntry]
}

/// Appends an entry to the history and trims oldest entries if count exceeds maxSize.
func appendAndTrim(entry: HistoryEntry, to history: HistoryFile, maxSize: Int) -> HistoryFile {
    var entries = history.entries
    entries.append(entry)
    if entries.count > maxSize {
        entries = Array(entries.suffix(maxSize))
    }
    return HistoryFile(entries: entries)
}

struct HistoryManager {
    let s3Client: S3Client
    let bucket: String
    let keyPrefix: String
    let maxHistorySize: Int

    /// Reads the existing history file from S3. Returns an empty HistoryFile if the file doesn't exist.
    /// Throws on other S3 errors.
    func readHistory() async throws -> HistoryFile {
        let key = "\(keyPrefix)/history.json"
        do {
            let output = try await s3Client.getObject(input: GetObjectInput(bucket: bucket, key: key))
            guard let body = output.body,
                  let data = try await body.readData() else {
                return HistoryFile(entries: [])
            }
            return try JSONDecoder().decode(HistoryFile.self, from: data)
        } catch is AWSS3.NoSuchKey {
            return HistoryFile(entries: [])
        }
    }

    /// Writes the history file to S3 as JSON with sorted keys.
    func writeHistory(_ history: HistoryFile) async throws {
        let key = "\(keyPrefix)/history.json"
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(history)
        _ = try await s3Client.putObject(input: PutObjectInput(
            body: .data(data),
            bucket: bucket,
            contentType: "application/json",
            key: key
        ))
    }

    /// Records a new history entry. Non-throwing — errors are logged internally.
    /// Skips writing if the most recent entry (by timestamp) already matches on artist, title, and artwork.
    func recordEntry(artist: String, title: String, artworkKey: String, timestamp: String, logger: Logger) async {
        var history: HistoryFile
        do {
            history = try await readHistory()
        } catch {
            logger.error("Failed to read history: \(error)")
            history = HistoryFile(entries: [])
        }

        // Deduplicate: if the latest entry matches, skip
        if let latest = history.entries.max(by: { $0.timestamp < $1.timestamp }),
           latest.artist == artist, latest.title == title, latest.artwork == artworkKey {
            logger.info("Duplicate of latest history entry, skipping")
            return
        }

        let entry = HistoryEntry(artist: artist, title: title, artwork: artworkKey, timestamp: timestamp)
        let updated = appendAndTrim(entry: entry, to: history, maxSize: maxHistorySize)

        do {
            try await writeHistory(updated)
        } catch {
            logger.error("Failed to write history: \(error)")
        }
    }
}
