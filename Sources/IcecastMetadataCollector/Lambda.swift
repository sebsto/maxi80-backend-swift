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

    private let streamURL: String
    private let authProvider: AppleMusicAuthProvider
    private let httpClient: MusicAPIClient
    private let s3Writer: S3Writer
    private let icecastReader: IcecastReader
    private let artworkDownloader: ArtworkDownloader
    private let historyManager: HistoryManager

    init() async throws {
        var logger = Logger(label: "IcecastMetadataCollector")
        logger.logLevel = Lambda.env("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ?? .info

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

        // Resolve bucket region and retrieve Apple Music secret in parallel.
        // These two async operations are independent — both only need env-derived values.
        // Snapshot logger as a let so child tasks can safely capture it
        let initLogger = logger

        async let resolvedBucketRegion: Region = {
            do {
                let tempConfig = try await S3Client.S3ClientConfig(region: configuredRegion.rawValue)
                let tempS3 = S3Client(config: tempConfig)
                let locationOutput = try await tempS3.getBucketLocation(
                    input: GetBucketLocationInput(bucket: bucket)
                )
                if let locationConstraint = locationOutput.locationConstraint?.rawValue,
                   !locationConstraint.isEmpty {
                    return Region(rawValue: locationConstraint)
                } else {
                    return .useast1
                }
            } catch {
                return configuredRegion
            }
        }()

        async let resolvedTokenFactory: JWTTokenFactory = {
            let secretsManager = try SecretsManager<AppleMusicSecret>(
                region: configuredRegion, logger: initLogger
            )
            let secret = try await secretsManager.getSecret(secretName: secretName)
            return JWTTokenFactory(
                secretKey: secret.privateKey,
                keyId: secret.keyId,
                issuerId: secret.teamId
            )
        }()

        let (bucketRegion, tokenFactory) = try await (resolvedBucketRegion, resolvedTokenFactory)
        logger.info("Bucket \(bucket) is in region \(bucketRegion)")

        // Initialize auth provider with token cache
        self.authProvider = AppleMusicAuthProvider(
            tokenFactory: tokenFactory,
            logger: logger
        )

        // Initialize HTTP client for Apple Music API
        self.httpClient = MusicAPIClient(logger: logger)

        // Initialize S3Writer (uses the resolved bucket region)
        let s3Config = try await S3Client.S3ClientConfig(region: bucketRegion.rawValue)
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
        context.logger.info("Invocation started")

        // Step 1: Read Icecast stream metadata
        let rawMetadata: String
        do {
            rawMetadata = try await icecastReader.readMetadata(from: streamURL)
        } catch {
            context.logger.error("Failed to read Icecast stream: \(error)")
            throw error
        }
        context.logger.info("Raw metadata: \(rawMetadata)")

        // Step 2: Parse metadata into artist/title
        let trackMetadata = parseTrackMetadata(rawMetadata)
        guard let artist = trackMetadata.artist, let title = trackMetadata.title else {
            context.logger.warning("Empty metadata — both artist and title are nil, skipping")
            return
        }
        context.logger.info("Parsed: artist=\(artist), title=\(title)")

        // Step 2b: Check if this is the same track as the latest history entry — skip everything if so
        do {
            let history = try await historyManager.readHistory()
            if let latest = history.entries.max(by: { $0.timestamp < $1.timestamp }),
               latest.artist == artist, latest.title == title {
                context.logger.info("Same track as latest history entry (\(artist) - \(title)), skipping")
                return
            }
        } catch {
            context.logger.warning("Failed to read history for dedup check, continuing: \(error)")
        }

        // Step 2c: If artist is "maxi80" or "maxi 80" (case-insensitive), skip Apple Music search
        let normalizedArtist = artist.lowercased().trimmingCharacters(in: .whitespaces)
        if normalizedArtist == "maxi80" || normalizedArtist == "maxi 80" {
            context.logger.info("Artist is Maxi 80, skipping Apple Music search")
            await recordHistory(artist: artist, title: title, file: "nocover.jpg")
            return
        }

        // Step 3: Check S3 cache — skip if already collected
        if try await s3Writer.exists(artist: artist, title: title) {
            context.logger.info("Cache hit for \(artist)/\(title), skipping")

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
            context.logger.warning("No search results for \(artist) - \(title), skipping")

            // Record history entry even when Apple Music has no results
            await recordHistory(artist: artist, title: title, file: "nocover.jpg")

            return
        }
        context.logger.info("Selected song: \(song.attributes.name) by \(song.attributes.artistName ?? "Unknown")")

        // Step 6: Download artwork (if available)
        let artworkData: Data?
        if let artwork = song.attributes.artwork {
            artworkData = try await artworkDownloader.download(artwork: artwork)
            context.logger.info("Downloaded artwork: \(artworkData!.count) bytes")
        } else {
            artworkData = nil
            context.logger.warning("No artwork available for \(artist) - \(title)")
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
        await recordHistory(artist: artist, title: title, file: artworkData != nil ? "artwork.jpg" : "nocover.jpg")

        context.logger.info("Successfully collected metadata for \(artist) - \(title)")
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
