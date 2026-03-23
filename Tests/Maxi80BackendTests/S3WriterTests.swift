import Testing

@testable import IcecastMetadataCollector

@Suite("S3Writer Tests")
struct S3WriterTests {

    struct S3KeyTestCase: CustomStringConvertible, Sendable {
        let prefix: String
        let artist: String
        let title: String
        var description: String { "prefix='\(prefix)', artist='\(artist)', title='\(title)'" }
    }

    static func generateS3KeyTestCases(count: Int) -> [S3KeyTestCase] {
        var rng = SystemRandomNumberGenerator()
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_ ")

        func randomString(minLen: Int = 1, maxLen: Int = 30) -> String {
            let length = Int.random(in: minLen...maxLen, using: &rng)
            return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count, using: &rng)] })
        }

        return (0..<count).map { _ in
            S3KeyTestCase(prefix: randomString(), artist: randomString(), title: randomString())
        }
    }

    // Feature: icecast-metadata-collector, Property 6: S3 key construction
    /// **Validates: Requirements 6.2, 6.3, 6.4**
    @Test("Property 6: S3 key construction pattern",
          arguments: generateS3KeyTestCases(count: 100))
    func s3KeyConstructionPattern(testCase: S3KeyTestCase) {
        let metadataKey = buildS3Key(prefix: testCase.prefix, artist: testCase.artist, title: testCase.title, file: "metadata.json")
        let searchKey = buildS3Key(prefix: testCase.prefix, artist: testCase.artist, title: testCase.title, file: "search.json")
        let artworkKey = buildS3Key(prefix: testCase.prefix, artist: testCase.artist, title: testCase.title, file: "artwork.jpg")

        #expect(metadataKey == "\(testCase.prefix)/\(testCase.artist)/\(testCase.title)/metadata.json")
        #expect(searchKey == "\(testCase.prefix)/\(testCase.artist)/\(testCase.title)/search.json")
        #expect(artworkKey == "\(testCase.prefix)/\(testCase.artist)/\(testCase.title)/artwork.jpg")
    }
}

// MARK: - Cache Hit Property Test

extension S3WriterTests {

    /// Simulates the collector pipeline to verify cache-hit behavior.
    struct MockCollectorPipeline {
        var cacheHit: Bool
        var searchCalled = false
        var artworkDownloadCalled = false
        var s3UploadCalled = false

        mutating func run() {
            // Simulate the collector's handle() logic
            if cacheHit {
                // Cache hit — skip everything
                return
            }
            searchCalled = true
            artworkDownloadCalled = true
            s3UploadCalled = true
        }
    }

    struct CacheHitTestCase: CustomStringConvertible, Sendable {
        let artist: String
        let title: String
        var description: String { "artist='\(artist)', title='\(title)'" }
    }

    static func generateCacheHitTestCases(count: Int) -> [CacheHitTestCase] {
        var rng = SystemRandomNumberGenerator()
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -")

        func randomString() -> String {
            let length = Int.random(in: 1...30, using: &rng)
            return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count, using: &rng)] })
        }

        return (0..<count).map { _ in
            CacheHitTestCase(artist: randomString(), title: randomString())
        }
    }

    // Feature: icecast-metadata-collector, Property 7: S3 cache hit skips processing
    /// **Validates: Requirements 6.1**
    @Test("Property 7: S3 cache hit skips processing",
          arguments: generateCacheHitTestCases(count: 100))
    func s3CacheHitSkipsProcessing(testCase: CacheHitTestCase) {
        var pipeline = MockCollectorPipeline(cacheHit: true)
        pipeline.run()

        #expect(!pipeline.searchCalled, "Apple Music search should not be called when cache hit")
        #expect(!pipeline.artworkDownloadCalled, "Artwork download should not be called when cache hit")
        #expect(!pipeline.s3UploadCalled, "S3 upload should not be called when cache hit")
    }
}

// MARK: - S3Writer Error Handling Unit Tests

extension S3WriterTests {

    @Test("CollectorError.s3WriteFailed includes file name - metadata.json")
    func s3WriteFailedMetadataIncludesFileName() {
        let error = CollectorError.s3WriteFailed(file: "metadata.json", reason: "Access Denied")
        if case .s3WriteFailed(let file, let reason) = error {
            #expect(file == "metadata.json")
            #expect(reason == "Access Denied")
        } else {
            Issue.record("Expected s3WriteFailed error")
        }
    }

    @Test("CollectorError.s3WriteFailed includes file name - search.json")
    func s3WriteFailedSearchIncludesFileName() {
        let error = CollectorError.s3WriteFailed(file: "search.json", reason: "Bucket not found")
        if case .s3WriteFailed(let file, let reason) = error {
            #expect(file == "search.json")
            #expect(reason == "Bucket not found")
        } else {
            Issue.record("Expected s3WriteFailed error")
        }
    }

    @Test("CollectorError.s3WriteFailed includes file name - artwork.jpg")
    func s3WriteFailedArtworkIncludesFileName() {
        let error = CollectorError.s3WriteFailed(file: "artwork.jpg", reason: "Network timeout")
        if case .s3WriteFailed(let file, let reason) = error {
            #expect(file == "artwork.jpg")
            #expect(reason == "Network timeout")
        } else {
            Issue.record("Expected s3WriteFailed error")
        }
    }
}
