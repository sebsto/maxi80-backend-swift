import Foundation
import Testing

@testable import Maxi80Backend

@Suite("Core Model Tests")
struct CoreModelTests {

    @Test("Station model encoding and decoding")
    func testStationCodable() throws {
        // Given
        let station = Station(
            name: "Test Station",
            streamUrl: "https://test.stream.com",
            image: "test-image.png",
            shortDesc: "Test short description",
            longDesc: "Test long description",
            websiteUrl: "https://test.website.com",
            donationUrl: "https://test.donation.com",
            defaultCoverUrl: "file://test-cover.png"
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(station)

        let decoder = JSONDecoder()
        let decodedStation = try decoder.decode(Station.self, from: data)

        // Then
        #expect(decodedStation.name == station.name)
        #expect(decodedStation.streamUrl == station.streamUrl)
        #expect(decodedStation.image == station.image)
        #expect(decodedStation.shortDesc == station.shortDesc)
        #expect(decodedStation.longDesc == station.longDesc)
        #expect(decodedStation.websiteUrl == station.websiteUrl)
        #expect(decodedStation.donationUrl == station.donationUrl)
        #expect(decodedStation.defaultCoverUrl == station.defaultCoverUrl)
    }

    @Test("Station default values")
    func testStationDefault() {
        // When
        let defaultStation = Station.default

        // Then
        #expect(defaultStation.name == "Maxi 80")
        #expect(defaultStation.streamUrl == "https://audio1.maxi80.com")
        #expect(defaultStation.image == "maxi80_nocover-b.png")
        #expect(defaultStation.shortDesc == "La radio de toute une génération")
        #expect(defaultStation.longDesc == "Le meilleur de la musique des années 80")
        #expect(defaultStation.websiteUrl == "https://maxi80.com")
        #expect(defaultStation.donationUrl == "https://www.maxi80.com/paypal.htm")
    }

    @Test("Maxi80Endpoint from path")
    func testMaxi80EndpointFromPath() {
        // When
        let stationEndpoint = Maxi80Endpoint.from(path: "/station")
        let searchEndpoint = Maxi80Endpoint.from(path: "/search")
        let invalidEndpoint = Maxi80Endpoint.from(path: "/invalid")

        // Then
        #expect(stationEndpoint == .station)
        #expect(searchEndpoint == .search)
        #expect(invalidEndpoint == nil)
    }

    @Test("Maxi80Endpoint raw values")
    func testMaxi80EndpointRawValues() {
        // Then
        #expect(Maxi80Endpoint.station.rawValue == "/station")
        #expect(Maxi80Endpoint.search.rawValue == "/search")
    }

    @Test("Maxi80Endpoint all cases")
    func testMaxi80EndpointAllCases() {
        // When
        let allCases = Maxi80Endpoint.allCases

        // Then
        #expect(allCases.count == 2)
        #expect(allCases.contains(.station))
        #expect(allCases.contains(.search))
    }
}
