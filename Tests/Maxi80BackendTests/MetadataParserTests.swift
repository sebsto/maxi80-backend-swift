import Testing
@testable import Maxi80Backend

@Suite("Metadata Parser Tests")
struct MetadataParserTests {
    
    @Test("Standard format with space-dash-space separator")
    func testStandardFormat() {
        let result = parseTrackMetadata("Rita Mitsouko - Andy")
        #expect(result.artist == "Rita Mitsouko")
        #expect(result.title == "Andy")
    }
    
    @Test("Format with dash separator only")
    func testDashSeparatorOnly() {
        let result = parseTrackMetadata("Freeez- I O U")
        #expect(result.artist == "Freeez")
        #expect(result.title == "I O U")
    }
    
    @Test("Multiple separators - uses last one")
    func testMultipleSeparators() {
        let result = parseTrackMetadata("Jean-Jacques Goldman - Au bout de mes rêves (actu 1983)")
        #expect(result.artist == "Jean-Jacques Goldman")
        #expect(result.title == "Au bout de mes rêves")
    }
    
    @Test("Maxi 80 artist normalization")
    func testMaxi80Normalization() {
        let result1 = parseTrackMetadata("Maxi 80 - Eighties Best Music")
        #expect(result1.artist == "Maxi80")
        #expect(result1.title == "Eighties Best Music")
        
        let result2 = parseTrackMetadata("Maxi80 - Le Meilleur Son 80s")
        #expect(result2.artist == "Maxi80")
        #expect(result2.title == "Le Meilleur Son 80s")
    }
    
    @Test("No separator - defaults to Maxi80 artist")
    func testNoSeparator() {
        let result1 = parseTrackMetadata("IN THE MIX avec DJ LUCKY")
        #expect(result1.artist == "Maxi80")
        #expect(result1.title == "IN THE MIX avec DJ LUCKY")
        
        let result2 = parseTrackMetadata("Jouez au Grand Quiz des Années 80 !")
        #expect(result2.artist == "Maxi80")
        #expect(result2.title == "Jouez au Grand Quiz des Années 80 !")
        
        let result3 = parseTrackMetadata("Devenez Sponsor de Maxi 80")
        #expect(result3.artist == "Maxi80")
        #expect(result3.title == "Devenez Sponsor de Maxi 80")
    }
    
    @Test("Edge cases")
    func testEdgeCases() {
        // Empty string
        let empty = parseTrackMetadata("")
        #expect(empty.artist == nil)
        #expect(empty.title == nil)
        
        // Whitespace only
        let whitespace = parseTrackMetadata("   ")
        #expect(whitespace.artist == nil)
        #expect(whitespace.title == nil)
        
        // Only separator
        let onlySeparator = parseTrackMetadata(" - ")
        #expect(onlySeparator.artist == nil)
        #expect(onlySeparator.title == nil)
    }
    
    @Test("Complex artist names with hyphens")
    func testComplexArtistNames() {
        let result1 = parseTrackMetadata("Lloyd Cole And The Commotions - Lost Weekend")
        #expect(result1.artist == "Lloyd Cole And The Commotions")
        #expect(result1.title == "Lost Weekend")
        
        let result2 = parseTrackMetadata("Philip Oakey & Giorgio Moroder - Good Bye Bad Times")
        #expect(result2.artist == "Philip Oakey & Giorgio Moroder")
        #expect(result2.title == "Good Bye Bad Times")
        
        let result3 = parseTrackMetadata("Michael Jackson - Diana Ross - Ease On Down The Road")
        #expect(result3.artist == "Michael Jackson - Diana Ross")
        #expect(result3.title == "Ease On Down The Road")
    }
    
    @Test("Parentheses removal from title")
    func testParenthesesRemoval() {
        let result1 = parseTrackMetadata("Jean-Jacques Goldman - Au bout de mes rêves (actu 1983)")
        #expect(result1.artist == "Jean-Jacques Goldman")
        #expect(result1.title == "Au bout de mes rêves")
        
        let result2 = parseTrackMetadata("Ub40 - I got you babe (actu 1985)")
        #expect(result2.artist == "Ub40")
        #expect(result2.title == "I got you babe")
        
        let result3 = parseTrackMetadata("Rod Stewart - Passion (maxi 45 T)")
        #expect(result3.artist == "Rod Stewart")
        #expect(result3.title == "Passion")
        
        // Test with no parentheses
        let result4 = parseTrackMetadata("Rita Mitsouko - Andy")
        #expect(result4.artist == "Rita Mitsouko")
        #expect(result4.title == "Andy")
        
        // Test with parentheses in middle (should not be removed)
        let result5 = parseTrackMetadata("Artist - Title (middle) end")
        #expect(result5.artist == "Artist")
        #expect(result5.title == "Title (middle) end")
    }
    
    @Test("Sample data validation")
    func testSampleData() {
        // Test a selection of actual metadata entries
        let samples = [
            ("Rita Mitsouko - Andy", "Rita Mitsouko", "Andy"),
            ("Freeez- I O U", "Freeez", "I O U"),
            ("Maxi 80 - Eighties Best Music", "Maxi80", "Eighties Best Music"),
            ("IN THE MIX avec DJ LUCKY", "Maxi80", "IN THE MIX avec DJ LUCKY"),
            ("Michael Jackson - Diana Ross - Ease On Down The Road", "Michael Jackson - Diana Ross", "Ease On Down The Road"),
            ("muriel dacq-là ou ça", "Maxi80", "muriel dacq-là ou ça"),
            ("Jean-Jacques Goldman - Au bout de mes rêves (actu 1983)", "Jean-Jacques Goldman", "Au bout de mes rêves"),
            ("Ub40 - I got you babe (actu 1985)", "Ub40", "I got you babe")
        ]
        
        for (input, expectedArtist, expectedTitle) in samples {
            let result = parseTrackMetadata(input)
            #expect(result.artist == expectedArtist, "Failed for input: \(input)")
            #expect(result.title == expectedTitle, "Failed for input: \(input)")
        }
    }
}
