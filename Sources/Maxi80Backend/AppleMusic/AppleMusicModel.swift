// https://developer.apple.com/documentation/applemusicapi

// MARK: - Search Response

public struct AppleMusicSearchResponse: Codable {
    public let meta: SearchMeta
    public let results: SearchResults
}

public struct SearchMeta: Codable {
    public let results: SearchMetaResults
}

public struct SearchMetaResults: Codable {
    public let order: [String]
    public let rawOrder: [String]
}

public struct SearchResults: Codable {
    public let artists: ResourceCollection<Artist>?
    public let albums: ResourceCollection<Album>?
    public let songs: ResourceCollection<Song>?
}

public struct ResourceCollection<T: Codable>: Codable {
    public let data: [T]
    public let href: String
    public let next: String?
}

// MARK: - Shared Types

public struct ResourceReference: Codable {
    public let href: String
    public let id: String
    public let type: String
}

public struct RelationshipCollection: Codable {
    public let data: [ResourceReference]
    public let href: String
    public let next: String?
}

// MARK: - Artist

public struct Artist: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: ArtistAttributes
    public let relationships: ArtistRelationships?
}

public struct ArtistAttributes: Codable {
    public let name: String
    public let genreNames: [String]
    public let url: String
    public let artwork: Song.Attributes.Artwork
}

public struct ArtistRelationships: Codable {
    public let albums: RelationshipCollection?
}

// MARK: - Album

public struct Album: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: AlbumAttributes
    public let relationships: AlbumRelationships?
}

public struct AlbumAttributes: Codable {
    public let name: String
    public let artistName: String
    public let genreNames: [String]
    public let releaseDate: String
    public let url: String
    public let artwork: Song.Attributes.Artwork
    public let trackCount: Int?
    public let isComplete: Bool?
    public let isSingle: Bool?
}

public struct AlbumRelationships: Codable {
    public let artists: RelationshipCollection?
    public let tracks: RelationshipCollection?
}

// MARK: - Song

public struct Song: Codable {
    public let id: String
    public let type: String
    public let href: String
    public let attributes: Attributes

    public struct Attributes: Codable {
        public let albumName: String
        public let artistName: String?
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
        public let hasCredits: Bool?
        public let hasLyrics: Bool?
        public let isAppleDigitalMaster: Bool?
        public let name: String
        public let previews: [Preview]

        public struct Artwork: Codable {
            public let width: Int
            public let height: Int
            public let url: String
            public let bgColor: String
            public let textColor1: String
            public let textColor2: String
            public let textColor3: String
            public let textColor4: String
        }

        public struct PlayParams: Codable {
            public let id: String
            public let kind: String
        }

        public struct Preview: Codable {
            public let url: String
        }
    }
}
