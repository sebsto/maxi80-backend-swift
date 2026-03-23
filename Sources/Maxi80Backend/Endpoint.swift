public enum Maxi80Endpoint: String, CaseIterable {
    case station = "/station"
    case artwork = "/artwork"

    public static func from(path: String) -> Self? {
        self.allCases.first { $0.rawValue == path }
    }
}
