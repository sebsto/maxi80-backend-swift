#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// https://developer.apple.com/documentation/applemusicapi

public enum AppleMusicSearchType: String, Sendable {
    case artists
    case songs
    case albums

    public static func items(searchTypes: [AppleMusicSearchType]) -> URLQueryItem {
        URLQueryItem(
            name: "types",
            value: String(searchTypes.map { $0.rawValue }.joined(separator: ","))
        )
    }
    public static func term(search: String) -> URLQueryItem {
        URLQueryItem(name: "term", value: search)
    }
}

public enum AppleMusicEndpoint: String, CaseIterable, Sendable {

    case test = "/test"
    case search = "/catalog/fr/search"

    public static func from(path: String) -> Self? {
        self.allCases.first { $0.rawValue == path }
    }

    private func baseURI() -> URL {
        URL(string: "https://api.music.apple.com/v1")!
    }

    public func url(args: [URLQueryItem] = []) -> URL {
        var result = baseURI().appendingPathComponent(self.rawValue)
        result.append(queryItems: args)
        return result

    }
}
