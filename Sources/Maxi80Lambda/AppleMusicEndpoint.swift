import Foundation 

// https://developer.apple.com/documentation/applemusicapi 

enum AppleMusicSearchType: String, Sendable {
    case artists
    case songs 
    case albums 

    static func items(searchTypes: [AppleMusicSearchType]) -> URLQueryItem {
        return URLQueryItem(name: "types", value: String(searchTypes.map { $0.rawValue }.joined(separator: ",")))
    }
    static func term(search: String) -> URLQueryItem {
        return URLQueryItem(name: "term", value: search)
    }
}

enum AppleMusicEndpoint: String, CaseIterable, Sendable {

    case test = "/test"
    case search = "/catalog/fr/search"

	static func from(path: String) -> Self? {
        return self.allCases.first{ $0.rawValue == path }
    }
}

extension AppleMusicEndpoint {

    private func baseURI() -> URL{
        return URL(string: "https://api.music.apple.com/v1")!
    }
    
    func url(args: [URLQueryItem] = []) -> URL {
        var result = baseURI().appendingPathComponent(self.rawValue)
        result.append(queryItems: args)
        return result
                        
    }
}