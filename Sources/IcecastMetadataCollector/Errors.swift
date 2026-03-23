#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum IcecastError: Error {
    case connectionFailed(reason: String)
    case missingMetaInt
    case timeout
    case noMetadata
    case invalidStreamTitle
}

enum CollectorError: Error {
    case missingEnvironmentVariable(String)
    case emptyMetadata
    case noSearchResults
    case artworkDownloadFailed(reason: String)
    case s3WriteFailed(file: String, reason: String)
    case secretRetrievalFailed(reason: String)
}
