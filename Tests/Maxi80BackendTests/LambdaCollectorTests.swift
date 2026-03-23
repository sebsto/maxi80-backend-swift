import Testing

@testable import IcecastMetadataCollector
@testable import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("IcecastMetadataCollector Lambda Handler Tests")
struct LambdaCollectorTests {

    // MARK: - Empty metadata skip

    @Test("Empty metadata skip — both artist and title nil")
    func emptyMetadataSkip() {
        // Simulate the handle() logic: parse metadata, check if both are nil
        let rawMetadata = ""
        let trackMetadata = parseTrackMetadata(rawMetadata)

        // When both artist and title are nil, the handler should return early
        // parseTrackMetadata returns nil for both on empty input
        let shouldSkip = trackMetadata.artist == nil && trackMetadata.title == nil
        #expect(shouldSkip, "Handler should skip when both artist and title are nil")
    }

    @Test("Empty metadata skip — whitespace-only input")
    func emptyMetadataSkipWhitespace() {
        let rawMetadata = "   "
        let trackMetadata = parseTrackMetadata(rawMetadata)

        let shouldSkip = trackMetadata.artist == nil && trackMetadata.title == nil
        #expect(shouldSkip, "Handler should skip when metadata is whitespace-only")
    }

    // MARK: - Zero search results skip

    @Test("Zero search results skip — nil songs")
    func zeroSearchResultsSkipNilSongs() {
        // Build a response with nil songs
        let response = AppleMusicSearchResponse(
            meta: SearchMeta(results: SearchMetaResults(order: [], rawOrder: [])),
            results: SearchResults(artists: nil, albums: nil, songs: nil)
        )

        let bestMatch = selectBestMatch(response)
        #expect(bestMatch == nil, "selectBestMatch should return nil when songs is nil")
    }

    @Test("Zero search results skip — empty songs array")
    func zeroSearchResultsSkipEmptySongs() {
        // Build a response with empty songs data
        let response = AppleMusicSearchResponse(
            meta: SearchMeta(results: SearchMetaResults(order: [], rawOrder: [])),
            results: SearchResults(
                artists: nil,
                albums: nil,
                songs: ResourceCollection<Song>(data: [], href: "/search", next: nil)
            )
        )

        let bestMatch = selectBestMatch(response)
        #expect(bestMatch == nil, "selectBestMatch should return nil when songs array is empty")
    }

    // MARK: - Missing environment variable error

    @Test("CollectorError.missingEnvironmentVariable contains variable name")
    func missingEnvironmentVariableError() {
        let error = CollectorError.missingEnvironmentVariable("STREAM_URL")
        if case .missingEnvironmentVariable(let name) = error {
            #expect(name == "STREAM_URL")
        } else {
            Issue.record("Expected missingEnvironmentVariable error")
        }
    }

    @Test("CollectorError.missingEnvironmentVariable for S3_BUCKET")
    func missingS3BucketError() {
        let error = CollectorError.missingEnvironmentVariable("S3_BUCKET")
        if case .missingEnvironmentVariable(let name) = error {
            #expect(name == "S3_BUCKET")
        } else {
            Issue.record("Expected missingEnvironmentVariable error")
        }
    }
}
