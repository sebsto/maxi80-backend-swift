import AWSLambdaEvents
import AWSLambdaRuntime
import AWSS3
import Logging
import Maxi80Backend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@main
struct IcecastMetadataCollector: LambdaHandler {

    private let logger: Logger
    private let streamURL: String
    private let authProvider: AppleMusicAuthProvider
    private let httpClient: MusicAPIClient
    private let s3Writer: S3Writer
    private let icecastReader: IcecastReader
    private let artworkDownloader: ArtworkDownloader
    private let historyManager: HistoryManager

    init() async throws {
        // Configure logger from LOG_LEVEL env var
        var logger = Logger(label: "IcecastMetadataCollector")
        logger.logLevel = Lambda.env("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ?? .info
        self.logger = logger

        // Read required environment variables
        guard let streamURL = Lambda.env("STREAM_URL") else {
            throw CollectorError.missingEnvironmentVariable("STREAM_URL")
        }
        self.streamURL = streamURL

        guard let bucket = Lambda.env("S3_BUCKET") else {
            throw CollectorError.missingEnvironmentVariable("S3_BUCKET")
        }

        let keyPrefix = Lambda.env("KEY_PREFIX") ?? "collected"
        let secretName = Lambda.env("SECRETS") ?? "Maxi80-AppleMusicKey"

        // Read the region from the environment variable
        let configuredRegion = Lambda.env("AWS_REGION").flatMap { Region(awsRegionName: $0) } ?? .eucentral1
        logger.trace("Configured region: \(configuredRegion)")

        // Resolve the actual bucket region via GetBucketLocation
        let bucketRegion: Region
        do {
            let tempConfig = try await S3Client.S3ClientConfiguration(region: configuredRegion.rawValue)
            let tempS3 = S3Client(config: tempConfig)
            let locationOutput = try await tempS3.getBucketLocation(input: GetBucketLocationInput(bucket: bucket))
            if let locationConstraint = locationOutput.locationConstraint?.rawValue, !locationConstraint.isEmpty {
                bucketRegion = Region(rawValue: locationConstraint)
            } else {
                // No constraint means us-east-1
                bucketRegion = .useast1
            }
            logger.info("Bucket \(bucket) is in region \(bucketRegion)")
        } catch {
            logger.warning("Failed to resolve bucket region, falling back to \(configuredRegion): \(error)")
            bucketRegion = configuredRegion
        }

        // Retrieve Apple Music secret from SecretsManager (uses the configured/deployment region)
        let resolvedTokenFactory: JWTTokenFactoryProtocol
        do {
            let secretsManager = try SecretsManager<AppleMusicSecret>(region: configuredRegion, logger: logger)
            let secret = try await secretsManager.getSecret(secretName: secretName)
            resolvedTokenFactory = JWTTokenFactory(
                secretKey: secret.privateKey,
                keyId: secret.keyId,
                issuerId: secret.teamId
            )
        } catch {
            logger.error("Can't read AppleMusic API key secret. Root cause: \(error)")
            throw CollectorError.secretRetrievalFailed(reason: "\(error)")
        }

        // Initialize auth provider with token cache
        self.authProvider = AppleMusicAuthProvider(
            tokenFactory: resolvedTokenFactory,
            logger: logger
        )

        // Initialize HTTP client for Apple Music API
        self.httpClient = MusicAPIClient(logger: logger)

        // Initialize S3Writer (uses the resolved bucket region)
        let s3Config = try await S3Client.S3ClientConfiguration(region: bucketRegion.rawValue)
        let s3Client = S3Client(config: s3Config)
        self.s3Writer = S3Writer(s3Client: s3Client, bucket: bucket, keyPrefix: keyPrefix, logger: logger)

        // Read MAX_HISTORY_SIZE from environment
        let maxHistorySize: Int
        if let maxHistorySizeStr = Lambda.env("MAX_HISTORY_SIZE"), let parsed = Int(maxHistorySizeStr) {
            maxHistorySize = parsed
        } else {
            logger.warning("MAX_HISTORY_SIZE not set or invalid, using default 100")
            maxHistorySize = 100
        }

        // Initialize HistoryManager
        self.historyManager = HistoryManager(
            s3Client: s3Client,
            bucket: bucket,
            keyPrefix: keyPrefix,
            maxHistorySize: maxHistorySize,
            logger: logger
        )

        // Initialize IcecastReader and ArtworkDownloader
        self.icecastReader = IcecastReader(logger: logger)
        self.artworkDownloader = ArtworkDownloader(logger: logger)

        logger.info("IcecastMetadataCollector initialized successfully")
    }

    func handle(_ event: EventBridgeEvent<CloudwatchDetails.Scheduled>, context: LambdaContext) async throws {
        logger.info("Invocation started")

        // Step 1: Read Icecast stream metadata
        let rawMetadata: String
        do {
            rawMetadata = try await icecastReader.readMetadata(from: streamURL)
        } catch {
            logger.error("Failed to read Icecast stream: \(error)")
            throw error
        }
        logger.info("Raw metadata: \(rawMetadata)")

        // Step 2: Parse metadata into artist/title
        let trackMetadata = parseTrackMetadata(rawMetadata)
        guard let artist = trackMetadata.artist, let title = trackMetadata.title else {
            logger.warning("Empty metadata — both artist and title are nil, skipping")
            return
        }
        logger.info("Parsed: artist=\(artist), title=\(title)")

        // Step 3: Check S3 cache — skip if already collected
        if try await s3Writer.exists(artist: artist, title: title) {
            logger.info("Cache hit for \(artist)/\(title), skipping")

            // Record history entry for cache hit
            await recordHistory(artist: artist, title: title, file: "artwork.jpg")

            return
        }

        // Step 4: Search Apple Music
        let searchFields = AppleMusicSearchType.items(searchTypes: [.songs])
        let searchTerms = AppleMusicSearchType.term(search: "\(artist) \(title)")

        let (searchData, _) = try await httpClient.apiCall(
            url: AppleMusicEndpoint.search.url(args: [searchFields, searchTerms]),
            method: .GET,
            body: nil,
            headers: try await authProvider.authorizationHeader(),
            timeout: 10
        )

        let searchResponse = try JSONDecoder().decode(AppleMusicSearchResponse.self, from: searchData)

        // Step 5: Select best match
        guard let song = selectBestMatch(searchResponse) else {
            logger.warning("No search results for \(artist) - \(title), skipping")

            // Record history entry even when Apple Music has no results
            await recordHistory(artist: artist, title: title, file: "nocover.jpg")

            return
        }
        logger.info("Selected song: \(song.attributes.name) by \(song.attributes.artistName ?? "Unknown")")

        // Step 6: Download artwork (if available)
        let artworkData: Data?
        if let artwork = song.attributes.artwork {
            artworkData = try await artworkDownloader.download(artwork: artwork)
            logger.info("Downloaded artwork: \(artworkData!.count) bytes")
        } else {
            artworkData = nil
            logger.warning("No artwork available for \(artist) - \(title)")
        }

        // Step 7: Upload all three files to S3
        let collectedMetadata = CollectedMetadata(
            rawMetadata: rawMetadata,
            artist: artist,
            title: title,
            collectedAt: Date.now.formatted(.iso8601)
        )

        try await s3Writer.writeMetadata(collectedMetadata, artist: artist, title: title)
        try await s3Writer.writeSearchResults(searchData, artist: artist, title: title)
        if let artworkData {
            try await s3Writer.writeArtwork(artworkData, artist: artist, title: title)
        }

        // Record history entry for cache miss
        await recordHistory(artist: artist, title: title, file: "artwork.jpg")

        logger.info("Successfully collected metadata for \(artist) - \(title)")
    }

    private func recordHistory(artist: String, title: String, file: String) async {
        let artworkKey = buildS3Key(prefix: s3Writer.keyPrefix, artist: artist, title: title, file: file)
        let timestamp = Date.now.formatted(.iso8601)
        await historyManager.recordEntry(artist: artist, title: title, artworkKey: artworkKey, timestamp: timestamp)
    }

    public static func main() async throws {
        let handler = try await IcecastMetadataCollector()
        let runtime = LambdaRuntime(lambdaHandler: handler)
        try await runtime.run()
    }
}
