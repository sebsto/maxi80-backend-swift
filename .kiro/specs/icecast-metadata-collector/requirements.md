# Requirements Document

## Introduction

The Icecast Metadata Collector is a new AWS Lambda function that connects to an Icecast audio stream, extracts the currently playing track metadata using the Icy-MetaData protocol, searches Apple Music for matching song information and artwork, and stores the results in S3. It runs on a 2-minute EventBridge schedule alongside the existing Maxi80Lambda, reusing the shared `Maxi80Backend` library for metadata parsing, Apple Music API access, and AWS service integration.

## Glossary

- **Collector_Lambda**: The new AWS Lambda function (`IcecastMetadataCollector` executable target) that orchestrates the metadata collection pipeline
- **Icecast_Reader**: The component responsible for connecting to an Icecast audio stream and extracting interleaved metadata using the Icy-MetaData protocol
- **Metadata_Parser**: The existing `parseTrackMetadata()` function from `Maxi80Backend` that parses raw metadata strings (e.g., "Artist - Title") into structured `TrackMetadata` with separate artist and title fields
- **Music_Search_Client**: The component that calls the Apple Music search API using the existing `MusicAPIClient`, `AppleMusicEndpoint`, and `AppleMusicAuthProvider` infrastructure from `Maxi80Backend`
- **Song_Selector**: An isolated function (not a protocol) that selects the best matching song from Apple Music search results
- **Artwork_Downloader**: The component that downloads cover artwork at the highest available resolution from Apple Music
- **S3_Writer**: The component that stores metadata, search results, and artwork files to an S3 bucket under a configurable key prefix
- **Icy-MetaData_Protocol**: The Icecast metadata interleaving protocol where the client sends an `Icy-MetaData: 1` request header, the server responds with an `icy-metaint` header indicating the byte interval between metadata blocks, and metadata blocks are interleaved with audio data at that interval
- **Metadata_Block**: A block of metadata in the Icecast stream where the first byte indicates the length divided by 16, followed by that many bytes of UTF-8 text in the format `StreamTitle='Artist - Title';`
- **Artwork_URL_Template**: The Apple Music artwork URL format containing `{w}` and `{h}` placeholders (e.g., `https://.../{w}x{h}bb.jpg`) that are replaced with pixel dimensions to request a specific resolution
- **SAM_Template**: The AWS SAM `template.yaml` file used to define and deploy all Lambda functions and associated resources
- **EventBridge_Rule**: An AWS EventBridge scheduled rule that triggers the Collector_Lambda on a recurring cron schedule

## Requirements

### Requirement 1: Icecast Stream Connection and Metadata Extraction

**User Story:** As a radio station operator, I want the system to connect to an Icecast audio stream and extract the currently playing track metadata, so that I can identify what song is playing without manual intervention.

#### Acceptance Criteria

1. WHEN the Collector_Lambda is invoked, THE Icecast_Reader SHALL connect to the stream URL specified in the `STREAM_URL` environment variable with an HTTP request containing the header `Icy-MetaData: 1`
2. WHEN the Icecast server responds, THE Icecast_Reader SHALL read the `icy-metaint` response header to determine the byte interval between metadata blocks
3. WHEN the Icecast_Reader has read the number of audio bytes indicated by `icy-metaint`, THE Icecast_Reader SHALL read the next metadata block by reading the length byte (value multiplied by 16) followed by that many bytes of metadata text
4. WHEN a metadata block is successfully read, THE Icecast_Reader SHALL extract the `StreamTitle` value from the metadata text (format: `StreamTitle='<value>';`)
5. WHEN the first metadata block containing a non-empty `StreamTitle` is extracted, THE Icecast_Reader SHALL close the stream connection and return the extracted metadata string
6. IF the stream connection fails or times out, THEN THE Icecast_Reader SHALL throw a descriptive error indicating the failure reason
7. IF the `icy-metaint` header is missing from the server response, THEN THE Icecast_Reader SHALL throw an error indicating the server does not support Icy-MetaData

### Requirement 2: Metadata Parsing

**User Story:** As a radio station operator, I want the raw Icecast metadata string to be parsed into structured artist and title fields, so that I can use them for searching and organizing files.

#### Acceptance Criteria

1. WHEN a raw metadata string is extracted from the Icecast stream, THE Metadata_Parser SHALL parse the string into a `TrackMetadata` struct with separate `artist` and `title` fields using the existing `parseTrackMetadata()` function from `Maxi80Backend`
2. IF the Metadata_Parser returns a `TrackMetadata` where both `artist` and `title` are nil, THEN THE Collector_Lambda SHALL skip further processing and log a warning

### Requirement 3: Apple Music Search

**User Story:** As a radio station operator, I want the system to search Apple Music for the currently playing track, so that I can retrieve song details and artwork.

#### Acceptance Criteria

1. WHEN a valid `TrackMetadata` with artist and title is available, THE Music_Search_Client SHALL search the Apple Music API for songs matching the artist and title using the existing `MusicAPIClient`, `AppleMusicEndpoint.search`, and `AppleMusicSearchType.songs` from `Maxi80Backend`
2. THE Music_Search_Client SHALL authenticate API requests using the existing `AppleMusicAuthProvider` pattern with `JWTTokenFactory` and `SecretsManager` reading the secret name from the `SECRETS` environment variable
3. THE Collector_Lambda SHALL read the Apple Music secret from SecretsManager once during initialization and cache the JWT token for reuse across invocations, following the same `TokenCache` actor pattern as the existing Maxi80Lambda, so that SecretsManager is not called on every invocation
4. IF the Apple Music search API returns an error or times out, THEN THE Music_Search_Client SHALL throw a descriptive error indicating the failure reason
4. IF the Apple Music search returns zero results, THEN THE Collector_Lambda SHALL log a warning and skip artwork download and S3 storage

### Requirement 4: Best Match Song Selection

**User Story:** As a radio station operator, I want the system to select the best matching song from the search results, so that the correct artwork and metadata are stored.

#### Acceptance Criteria

1. WHEN the Apple Music search returns one or more song results, THE Song_Selector SHALL select the first song entry from the results array as the best match
2. THE Song_Selector SHALL be implemented as an isolated function (not a protocol) to allow future replacement with more sophisticated matching logic

### Requirement 5: Artwork Download at Highest Resolution

**User Story:** As a radio station operator, I want the system to download the album artwork at the highest possible resolution, so that the stored cover images are of maximum quality.

#### Acceptance Criteria

1. WHEN a song is selected, THE Artwork_Downloader SHALL construct the artwork download URL by replacing `{w}` with the `width` value and `{h}` with the `height` value from the song's `artwork` attributes in the Apple Music response
2. THE Artwork_Downloader SHALL download the artwork image data from the constructed URL using `AsyncHTTPClient`
3. IF the artwork download fails, THEN THE Artwork_Downloader SHALL throw a descriptive error indicating the failure reason

### Requirement 6: S3 Storage

**User Story:** As a radio station operator, I want the collected metadata, search results, and artwork to be stored in S3, so that they are persisted and accessible for later use.

#### Acceptance Criteria

1. BEFORE performing the Apple Music search, artwork download, or S3 uploads, THE Collector_Lambda SHALL check if the S3 key `<KEY_PREFIX>/<artist>/<title>/metadata.json` already exists in the bucket. IF it exists, THE Collector_Lambda SHALL skip the Apple Music search, artwork download, and all S3 uploads, and log that the entry was already cached
2. THE S3_Writer SHALL store a `metadata.json` file at the S3 key `<KEY_PREFIX>/<artist>/<title>/metadata.json` containing both the raw Icecast metadata string and the parsed artist and title fields
2. THE S3_Writer SHALL store a `search.json` file at the S3 key `<KEY_PREFIX>/<artist>/<title>/search.json` containing the full Apple Music search response JSON
3. THE S3_Writer SHALL store an `artwork.jpg` file at the S3 key `<KEY_PREFIX>/<artist>/<title>/artwork.jpg` containing the downloaded cover image at highest resolution
4. THE S3_Writer SHALL read the bucket name from the `S3_BUCKET` environment variable and the key prefix from the `KEY_PREFIX` environment variable
5. IF any S3 upload fails, THEN THE S3_Writer SHALL throw a descriptive error indicating which file failed and the failure reason

### Requirement 7: Lambda Configuration and Deployment

**User Story:** As a developer, I want the new Lambda to be deployed via SAM alongside the existing Maxi80Lambda, so that both functions share the same deployment pipeline.

#### Acceptance Criteria

1. THE Collector_Lambda SHALL be defined as a separate executable target named `IcecastMetadataCollector` in `Package.swift` with a dependency on `Maxi80Backend`, `AWSLambdaRuntime`, and `AWSLambdaEvents`
2. THE SAM_Template SHALL define a new `AWS::Serverless::Function` resource for the Collector_Lambda with `BuildMethod: makefile` and `Runtime: provided.al2023` on `arm64` architecture
3. THE SAM_Template SHALL configure the Collector_Lambda with `LoggingConfig` to use JSON structured logging format (`LogFormat: JSON`) with appropriate `ApplicationLogLevel` and `SystemLogLevel`, enabling CloudWatch to capture logs as searchable key-value pairs
4. THE SAM_Template SHALL configure an EventBridge_Rule that triggers the Collector_Lambda every 2 minutes using a `Schedule` event
4. THE SAM_Template SHALL configure the Collector_Lambda with environment variables: `STREAM_URL`, `S3_BUCKET`, `KEY_PREFIX`, `SECRETS`, `LOG_LEVEL`, and `AWS_REGION`
5. THE SAM_Template SHALL grant the Collector_Lambda IAM permissions to read secrets from SecretsManager and to put objects in the S3 bucket
6. THE Makefile SHALL include a build target for the `IcecastMetadataCollector` product that packages the Lambda binary to the SAM artifacts directory

### Requirement 8: Lambda Execution Lifecycle

**User Story:** As a developer, I want the Lambda to start reading the Icecast stream immediately on invocation and stop as soon as metadata is collected, so that execution time and cost are minimized.

#### Acceptance Criteria

1. WHEN the Collector_Lambda is invoked by the EventBridge_Rule, THE Collector_Lambda SHALL start the Icecast stream reading and the SecretsManager secret retrieval in parallel (e.g., using `async let` or a task group) so that neither blocks the other
2. IF the Icecast metadata is received before the secret is available, THE Collector_Lambda SHALL await the secret retrieval to complete before proceeding to the Apple Music API call
3. WHEN the Icecast_Reader has extracted the first valid metadata, THE Collector_Lambda SHALL proceed to parsing, searching, downloading, and storing without reading further stream data
3. THE Collector_Lambda SHALL read the `LOG_LEVEL` environment variable and configure the logger accordingly using the same pattern as the existing Maxi80Lambda (`Lambda.env("LOG_LEVEL")`)
4. THE Collector_Lambda SHALL read the `AWS_REGION` environment variable and use the `Region` type from `Maxi80Backend` for AWS client configuration

### Requirement 9: Cross-Platform Compatibility (macOS and Linux)

**User Story:** As a developer, I want the new Lambda code to compile and run on both macOS (for local testing) and Linux (for Lambda deployment), so that I can develop and test locally before deploying.

#### Acceptance Criteria

1. THE Collector_Lambda SHALL use conditional imports for Foundation: `#if canImport(FoundationEssentials) import FoundationEssentials #else import Foundation #endif` and `#if canImport(FoundationNetworking) import FoundationNetworking #endif` following the same pattern as the existing codebase
2. THE Icecast_Reader SHALL use `AsyncHTTPClient` (not URLSession) for streaming the Icecast metadata, ensuring compatibility on both macOS and Linux
3. THE Artwork_Downloader SHALL use `AsyncHTTPClient` for downloading artwork, consistent with the existing `MusicAPIClient` pattern in `Maxi80Backend`
4. THE Collector_Lambda SHALL compile and run correctly on both macOS (for testing) and Linux (for Lambda deployment)

### Requirement 10: Swift 6 Concurrency Compliance

**User Story:** As a developer, I want the new Lambda code to be fully Swift 6 concurrency compliant, so that it compiles without warnings under strict concurrency checking.

#### Acceptance Criteria

1. THE Collector_Lambda SHALL compile without warnings under Swift 6 strict concurrency checking (swift-tools-version: 6.2)
2. THE Collector_Lambda SHALL use Swift Concurrency (async/await, actors) for all asynchronous operations including stream reading, API calls, image downloads, and S3 uploads
