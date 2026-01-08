public struct Station: Codable, Sendable {
    public let name: String
    public let streamUrl: String
    public let image: String
    public let shortDesc: String
    public let longDesc: String
    public let websiteUrl: String
    public let donationUrl: String
    public static let `default` = Station(
        name: "Maxi 80",
        streamUrl: "https://audio1.maxi80.com",
        image: "maxi80_nocover-b.png",
        shortDesc: "La radio de toute une génération",
        longDesc: "Le meilleur de la musique des années 80",
        websiteUrl: "https://maxi80.com",
        donationUrl: "https://www.maxi80.com/paypal.htm"
    )

}
