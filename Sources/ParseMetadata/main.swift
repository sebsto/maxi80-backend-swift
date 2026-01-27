import Foundation
import Maxi80Backend

struct ParsedMetadata: Codable {
    let original: String
    let artist: String?
    let title: String?
}

// Main script
let metadataFile = "metadata.txt"
let outputDir = "search_results"

// Create output directory
let fileManager = FileManager.default
try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// Read metadata file
let content = try String(contentsOfFile: metadataFile, encoding: .utf8)
let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

print("Processing \(lines.count) metadata entries...")

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted

for (index, line) in lines.enumerated() {
    let metadata = parseTrackMetadata(line)

    let outputFile = "\(outputDir)/\(String(format: "%03d", index + 1))_parsed.json"

    let result = ParsedMetadata(
        original: line,
        artist: metadata.artist,
        title: metadata.title
    )

    let jsonData = try encoder.encode(result)
    try jsonData.write(to: URL(fileURLWithPath: outputFile))

    print("[\(index + 1)/\(lines.count)] \(line) -> \(outputFile)")
}

print("Parsing complete! Results saved to \(outputDir)/")
