// https://developer.apple.com/documentation/applemusicapi

public struct Song: Decodable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: Attributes

    public struct Attributes: Decodable {
        public let albumName: String
        public let genreNames: [String]
        public let trackNumber: Int
        public let durationInMillis: Int
        public let releaseDate: String
        public let isrc: String
        public let artwork: Artwork
        public let composerName: String?
        public let url: String
        public let playParams: PlayParams
        public let discNumber: Int
        public let hasCredits: Bool
        public let hasLyrics: Bool
        public let isAppleDigitalMaster: Bool
        public let name: String
        public let previews: [Preview]

        public struct Artwork: Decodable {
            public let width: Int
            public let height: Int
            public let url: String
            public let bgColor: String
            public let textColor1: String
            public let textColor2: String
            public let textColor3: String
            public let textColor4: String
        }

        public struct PlayParams: Decodable {
            public let id: String
            public let kind: String
        }

        public struct Preview: Decodable {
            public let url: String
        }
    }
}
