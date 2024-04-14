import Foundation 

enum AppleMusicEndpoint: String, CaseIterable {
    case test = "/test"
    case search = "/search"

	static func from(path: String) -> Self? {
        return self.allCases.first{ $0.rawValue == path }
    }
}

extension AppleMusicEndpoint {

    private func baseURI() -> URL{
        return URL(string: "https://api.music.apple.com/v1")!
    }
    
    func url() -> URL {
        return baseURI().appendingPathComponent(self.rawValue)
    }
}