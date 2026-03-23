#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct CollectedMetadata: Codable, Sendable {
    let rawMetadata: String      // Original Icecast StreamTitle value
    let artist: String           // Parsed artist name
    let title: String            // Parsed title
    let collectedAt: String      // ISO 8601 timestamp
}
