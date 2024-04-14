public enum Endpoint: String, CaseIterable {
    case station = "/station"
    case search = "/search"

	public static func from(path: String) -> Self? {
        return self.allCases.first{ $0.rawValue == path }
    }
}