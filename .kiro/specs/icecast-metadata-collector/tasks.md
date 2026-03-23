# Implementation Plan: Icecast Metadata Collector

## Overview

Implement a new AWS Lambda function (`IcecastMetadataCollector`) that connects to an Icecast audio stream on a 2-minute EventBridge schedule, extracts the currently playing track metadata, searches Apple Music, downloads artwork, and stores results in S3. The implementation reuses `Maxi80Backend` extensively and follows the same patterns as the existing `Maxi80Lambda`.

## Tasks

- [x] 1. Add the new executable target and source directory
  - [x] 1.1 Add `IcecastMetadataCollector` executable product and target to `Package.swift`
    - Add `.executable(name: "IcecastMetadataCollector", ...)` to products array
    - Add `.executableTarget(name: "IcecastMetadataCollector", ...)` to targets with dependencies on `AWSLambdaRuntime`, `AWSLambdaEvents`, `AsyncHTTPClient`, `Logging`, `Maxi80Backend`
    - Add `AWSS3` dependency to the new target for S3 operations
    - _Requirements: 7.1_

  - [x] 1.2 Create error types in `Sources/IcecastMetadataCollector/Errors.swift`
    - Define `IcecastError` enum with cases: `connectionFailed(reason:)`, `missingMetaInt`, `timeout`, `noMetadata`, `invalidStreamTitle`
    - Define `CollectorError` enum with cases: `missingEnvironmentVariable(String)`, `emptyMetadata`, `noSearchResults`, `artworkDownloadFailed(reason:)`, `s3WriteFailed(file:reason:)`, `secretRetrievalFailed(reason:)`
    - Use conditional Foundation imports (`#if canImport(FoundationEssentials)`)
    - _Requirements: 1.6, 1.7, 5.3, 6.6, 9.1_

  - [x] 1.3 Create `CollectedMetadata` model in `Sources/IcecastMetadataCollector/CollectedMetadata.swift`
    - Define `Codable, Sendable` struct with fields: `rawMetadata`, `artist`, `title`, `collectedAt` (ISO 8601 string)
    - _Requirements: 6.2_

- [x] 2. Implement IcecastReader
  - [x] 2.1 Create `Sources/IcecastMetadataCollector/IcecastReader.swift`
    - Implement `IcecastReader` struct with `logger: Logger` property
    - Implement `readMetadata(from streamURL: String) async throws -> String`
    - Build `HTTPClientRequest` with `Icy-MetaData: 1` header
    - Execute via `HTTPClient.shared.execute()` with streaming response body
    - Read `icy-metaint` response header; throw `IcecastError.missingMetaInt` if absent
    - Iterate over response body `AsyncSequence` of `ByteBuffer`, maintaining a byte counter
    - After `icy-metaint` audio bytes, read length byte (value × 16), then read that many metadata bytes
    - Extract `StreamTitle='...'` value from metadata text
    - Return first non-empty StreamTitle and close connection
    - Throw appropriate `IcecastError` cases on failure
    - Use conditional Foundation imports and `AsyncHTTPClient` (not URLSession)
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 9.1, 9.2, 10.2_

  - [x] 2.2 Write property test: Icy-MetaData request header
    - **Property 1: Icy-MetaData request header**
    - For any stream URL string, verify the HTTP request constructed by `IcecastReader` contains the header `Icy-MetaData: 1`
    - **Validates: Requirements 1.1**

  - [x] 2.3 Write property test: Icecast byte stream round trip
    - **Property 2: Icecast protocol byte stream parsing (round trip)**
    - For any valid icy-metaint value, audio bytes of that length, and metadata string, construct a synthetic Icecast byte stream and verify parsing produces the original metadata string
    - **Validates: Requirements 1.2, 1.3**

  - [x] 2.4 Write property test: StreamTitle extraction
    - **Property 3: StreamTitle extraction**
    - For any non-empty string value, wrap it in `StreamTitle='<value>';` format and verify the parser returns exactly `<value>`
    - **Validates: Requirements 1.4**

  - [x] 2.5 Write unit tests for IcecastReader error handling
    - Test `IcecastError.connectionFailed` on bad URL
    - Test `IcecastError.missingMetaInt` when header is absent
    - Test reader returns after first valid StreamTitle (stops reading)
    - _Requirements: 1.6, 1.7, 8.3_

- [x] 3. Implement song selector and artwork downloader
  - [x] 3.1 Create `Sources/IcecastMetadataCollector/SongSelector.swift`
    - Implement top-level function `selectBestMatch(_ response: AppleMusicSearchResponse) -> Song?`
    - Return first element from `response.results.songs?.data` or nil if empty
    - _Requirements: 4.1, 4.2_

  - [x] 3.2 Write property test: Song selector returns first element
    - **Property 4: Song selector returns first element**
    - For any non-empty array of `Song` objects, verify `selectBestMatch()` returns the first element; for empty/nil, returns nil
    - **Validates: Requirements 4.1**

  - [x] 3.3 Create `Sources/IcecastMetadataCollector/ArtworkDownloader.swift`
    - Implement `ArtworkDownloader` struct with `logger: Logger` property
    - Implement `download(artwork: Song.Attributes.Artwork) async throws -> Data`
    - Replace `{w}` with `artwork.width` and `{h}` with `artwork.height` in artwork URL template
    - Download via `HTTPClient.shared.execute()` using `AsyncHTTPClient`
    - Throw `CollectorError.artworkDownloadFailed` on failure
    - Use conditional Foundation imports
    - _Requirements: 5.1, 5.2, 5.3, 9.1, 9.3_

  - [x] 3.4 Write property test: Artwork URL template substitution
    - **Property 5: Artwork URL template substitution**
    - For any artwork URL template containing `{w}` and `{h}` and any positive width/height, verify the constructed URL has placeholders replaced and no remaining `{w}` or `{h}`
    - **Validates: Requirements 5.1**

  - [x] 3.5 Write unit tests for artwork download failure
    - Test `CollectorError.artworkDownloadFailed` on HTTP error using `MockHTTPClient`
    - _Requirements: 5.3_

- [x] 4. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement S3Writer
  - [x] 5.1 Create `Sources/IcecastMetadataCollector/S3Writer.swift`
    - Implement `S3Writer` struct with `s3Client: S3Client`, `bucket: String`, `keyPrefix: String`, `logger: Logger`
    - Implement `exists(artist:title:) async throws -> Bool` using HEAD object on `<keyPrefix>/<artist>/<title>/metadata.json`
    - Implement `writeMetadata(_:artist:title:) async throws` to PUT `metadata.json`
    - Implement `writeSearchResults(_:artist:title:) async throws` to PUT `search.json`
    - Implement `writeArtwork(_:artist:title:) async throws` to PUT `artwork.jpg`
    - Read bucket from `S3_BUCKET` and prefix from `KEY_PREFIX` environment variables
    - Throw `CollectorError.s3WriteFailed(file:reason:)` on failure
    - Use `AWSS3.S3Client` from aws-sdk-swift
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6_

  - [x] 5.2 Write property test: S3 key construction pattern
    - **Property 6: S3 key construction**
    - For any key prefix, artist, and title, verify S3 keys follow `<prefix>/<artist>/<title>/metadata.json`, `search.json`, `artwork.jpg` patterns
    - **Validates: Requirements 6.2, 6.3, 6.4**

  - [x] 5.3 Write property test: S3 cache hit skips processing
    - **Property 7: S3 cache hit skips processing**
    - For any artist/title where S3 cache check returns true, verify the collector does not invoke Apple Music search, artwork download, or S3 uploads
    - **Validates: Requirements 6.1**

  - [x] 5.4 Write unit tests for S3Writer error handling
    - Test `CollectorError.s3WriteFailed` includes file name in error
    - _Requirements: 6.6_

- [x] 6. Implement Lambda handler and wire everything together
  - [x] 6.1 Create `Sources/IcecastMetadataCollector/Lambda.swift`
    - Implement `@main struct IcecastMetadataCollector: LambdaHandler` using the same pattern as existing `Maxi80Lambda`
    - `handle()` event type: `EventBridgeEvent<CloudwatchDetails.Scheduled>`
    - In `init() async throws`: configure logger from `LOG_LEVEL`, read `AWS_REGION`, `STREAM_URL`, `S3_BUCKET`, `KEY_PREFIX`, `SECRETS` env vars
    - In `init()`: retrieve Apple Music secret from `SecretsManager<AppleMusicSecret>`, create `JWTTokenFactory` and `AppleMusicAuthProvider` with `TokenCache` actor
    - In `init()`: create `S3Writer`, `IcecastReader`, `ArtworkDownloader`, `MusicAPIClient`
    - Throw `CollectorError.missingEnvironmentVariable` if required env vars are missing
    - Implement `static func main() async throws` that creates the handler and runs `LambdaRuntime(lambdaHandler:)`
    - In `handle(_:context:)`: read Icecast stream via `IcecastReader`
    - Parse metadata with `parseTrackMetadata()` from `Maxi80Backend`; skip if both artist and title are nil (log warning)
    - Check S3 cache via `S3Writer.exists()`; skip if already cached (log info)
    - Search Apple Music via `MusicAPIClient` with `AppleMusicAuthProvider`; skip if zero results (log warning)
    - Select best match via `selectBestMatch()`
    - Download artwork via `ArtworkDownloader`
    - Upload `metadata.json`, `search.json`, `artwork.jpg` via `S3Writer`
    - Use `async let` for parallel initialization where applicable (Requirement 8.1)
    - Use conditional Foundation imports throughout
    - Ensure Swift 6 concurrency compliance (async/await, actors, Sendable)
    - _Requirements: 1.1, 2.1, 2.2, 3.1, 3.2, 3.3, 6.1, 7.1, 8.1, 8.2, 8.3, 8.4, 9.1, 9.4, 10.1, 10.2_

  - [x] 6.2 Write property test: Token cache reuse
    - **Property 8: Token cache reuse**
    - For any sequence of `authorizationHeader()` calls where the cached token is valid, verify the same token is returned without calling `generateJWTString()` again
    - **Validates: Requirements 3.3**

  - [x] 6.3 Write unit tests for Lambda handler
    - Test empty metadata skip (artist and title both nil → log warning, return early)
    - Test zero search results skip (log warning, return early)
    - Test missing environment variable error
    - _Requirements: 2.2, 3.5, 7.5_

- [x] 7. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Update SAM template and Makefile for deployment
  - [x] 8.1 Add `IcecastMetadataCollector` function resource to `template.yaml`
    - Add new `AWS::Serverless::Function` resource with `Handler: bootstrap`, `Runtime: provided.al2023`, `Architectures: [arm64]`, `BuildMethod: makefile`
    - Set `MemorySize: 128` and `Timeout: 115` (just under the 2-minute schedule interval)
    - Configure `LoggingConfig` with `LogFormat: JSON`, `ApplicationLogLevel: INFO`, `SystemLogLevel: WARN`
    - Add `Schedule` event with `rate(2 minutes)` for EventBridge trigger
    - Set environment variables: `STREAM_URL`, `S3_BUCKET`, `KEY_PREFIX`, `SECRETS`, `LOG_LEVEL`
    - Add IAM policies for `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret`, `s3:PutObject`, `s3:HeadObject`
    - _Requirements: 7.2, 7.3, 7.4, 7.5, 7.6_

  - [x] 8.2 Add build target to `Makefile`
    - Add `build-IcecastMetadataCollector` target that builds the `IcecastMetadataCollector` product and copies bootstrap to `$(ARTIFACTS_DIR)/`
    - _Requirements: 7.7_

- [x] 9. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests validate universal correctness properties from the design document
- Unit tests validate specific examples and edge cases
- The implementation reuses `Maxi80Backend` components: `parseTrackMetadata()`, `MusicAPIClient`, `AppleMusicEndpoint`, `AppleMusicSearchType`, `JWTTokenFactory`, `SecretsManager`, `AppleMusicAuthProvider` pattern, `Region`, `HTTPClientProtocol`
- Existing test mocks (`MockHTTPClient`, `MockJWTTokenFactory`) should be reused where applicable
- All new code must use conditional Foundation imports and `AsyncHTTPClient` for cross-platform compatibility
- All new code must be Swift 6 concurrency compliant
