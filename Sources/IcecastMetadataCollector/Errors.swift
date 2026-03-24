#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum IcecastError: Error, CustomStringConvertible {
    case connectionFailed(reason: String)
    case missingMetaInt
    case timeout
    case noMetadata
    case invalidStreamTitle

    var description: String {
        switch self {
        case .connectionFailed(let reason): return "Icecast connection failed: \(reason)"
        case .missingMetaInt: return "Icecast server response missing icy-metaint header"
        case .timeout: return "Icecast stream reading timed out"
        case .noMetadata: return "No metadata found in Icecast stream"
        case .invalidStreamTitle: return "Invalid StreamTitle format in Icecast metadata"
        }
    }
}

enum CollectorError: Error, CustomStringConvertible {
    case missingEnvironmentVariable(String)
    case emptyMetadata
    case noSearchResults
    case artworkDownloadFailed(reason: String)
    case s3WriteFailed(file: String, reason: String)
    case secretRetrievalFailed(reason: String)

    var description: String {
        switch self {
        case .missingEnvironmentVariable(let name): return "Missing required environment variable: \(name)"
        case .emptyMetadata: return "Received empty metadata from Icecast stream"
        case .noSearchResults: return "No Apple Music search results found"
        case .artworkDownloadFailed(let reason): return "Artwork download failed: \(reason)"
        case .s3WriteFailed(let file, let reason): return "S3 write failed for \(file): \(reason)"
        case .secretRetrievalFailed(let reason): return "Secret retrieval failed: \(reason)"
        }
    }
}
