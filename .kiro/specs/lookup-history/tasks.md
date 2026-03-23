# Implementation Plan: Lookup History

## Overview

Add lookup history tracking to the `IcecastMetadataCollector` Lambda. This involves creating `HistoryEntry`, `HistoryFile`, and `HistoryManager` types in a new file, modifying `Lambda.swift` to wire in history recording (and fix the existing `ISO8601DateFormatter` usage), updating `template.yaml` for the new IAM permission and env var, and adding property-based and unit tests.

## Tasks

- [x] 1. Create HistoryManager.swift with data models and history logic
  - [x] 1.1 Create `HistoryEntry` and `HistoryFile` structs
    - Create `Sources/IcecastMetadataCollector/HistoryManager.swift`
    - Add `#if canImport(FoundationEssentials)` conditional import
    - Define `HistoryEntry` struct (Codable, Sendable, Equatable) with `artist`, `title`, `artwork`, `timestamp` String fields
    - Define `HistoryFile` struct (Codable, Sendable, Equatable) with `var entries: [HistoryEntry]`
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [x] 1.2 Implement `HistoryManager` struct with `appendAndTrim` static method
    - Add `HistoryManager` struct with properties: `s3Client` (S3Client), `bucket` (String), `keyPrefix` (String), `maxHistorySize` (Int), `logger` (Logger)
    - Implement `static func appendAndTrim(entry: HistoryEntry, to history: HistoryFile, maxSize: Int) -> HistoryFile` as a pure function that appends the entry and trims oldest entries from the beginning of the array when count exceeds maxSize
    - _Requirements: 2.1, 2.2, 2.3, 4.3, 4.4_

  - [x] 1.3 Implement `readHistory`, `writeHistory`, and `recordEntry` methods
    - Implement `readHistory() async throws -> HistoryFile` that reads `<keyPrefix>/history.json` from S3, returns empty `HistoryFile` on NoSuchKey
    - Implement `writeHistory(_ history: HistoryFile) async throws` that writes JSON to S3 using `JSONEncoder` with `.sortedKeys`
    - Implement `recordEntry(artist:title:artworkKey:timestamp:) async` as non-throwing: calls readHistory (falls back to empty on error), calls appendAndTrim, calls writeHistory (logs error on failure)
    - _Requirements: 2.1, 3.1, 3.2, 3.3, 5.1, 5.2, 5.3, 7.2_

  - [x] 1.4 Write property test: Serialization round-trip (Property 1)
    - **Property 1: Serialization round-trip**
    - Generate 100+ random `HistoryFile` instances with varying entry counts and arbitrary non-empty string fields
    - Encode to JSON with `JSONEncoder` (`.sortedKeys`), decode back with `JSONDecoder`, assert equality
    - Add test to `Tests/Maxi80BackendTests/HistoryManagerTests.swift`
    - **Validates: Requirements 7.1, 1.4**

  - [x] 1.5 Write property test: JSON structure contains required keys (Property 2)
    - **Property 2: Serialized JSON structure contains required keys**
    - Generate 100+ random `HistoryEntry` instances, encode to JSON, parse raw JSON dictionary, assert exactly the keys `artist`, `title`, `artwork`, `timestamp` are present with String values
    - **Validates: Requirements 1.1, 1.2**

  - [x] 1.6 Write property test: Size invariant after append-and-trim (Property 3)
    - **Property 3: Size invariant after append-and-trim**
    - Generate 100+ random `HistoryFile` instances of varying sizes and random `maxSize >= 1`, call `appendAndTrim`, assert result count equals `min(n + 1, maxSize)`
    - **Validates: Requirements 2.1, 4.3**

  - [x] 1.7 Write property test: Ordering — new entry is last, oldest trimmed first (Property 4)
    - **Property 4: Ordering — new entry is last, oldest entries are trimmed first**
    - Generate 100+ random histories, call `appendAndTrim`, assert last element is the new entry and preceding entries are a suffix of the original array
    - **Validates: Requirements 2.3, 4.4**

  - [x] 1.8 Write property test: Duplicate entries are preserved (Property 5)
    - **Property 5: Duplicate entries are preserved**
    - Generate 100+ random histories, pick an existing entry's artist/title, append a new entry with the same artist/title, assert both entries are present in the result
    - **Validates: Requirements 2.2**

  - [x] 1.9 Write unit tests for edge cases
    - Test `appendAndTrim` with empty `HistoryFile` produces exactly one entry
    - Test trimming at boundary: history at exactly `maxSize`, append one, verify count stays at `maxSize`
    - Test `appendAndTrim` with `maxSize = 1` always produces single-entry result
    - _Requirements: 4.3, 4.4, 3.3_

- [x] 2. Checkpoint - Verify HistoryManager compiles and tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 3. Integrate HistoryManager into Lambda.swift and update template.yaml
  - [x] 3.1 Update `template.yaml` with new IAM permission and env var
    - Add `s3:GetObject` to the existing S3 policy actions for `IcecastMetadataCollector`
    - Add `MAX_HISTORY_SIZE: "100"` to the `IcecastMetadataCollector` environment variables
    - _Requirements: 6.1, 6.2_

  - [x] 3.2 Modify `Lambda.swift` to initialize `HistoryManager` and fix ISO 8601 formatting
    - Add `private let historyManager: HistoryManager` property to `IcecastMetadataCollector`
    - In `init()`, read `MAX_HISTORY_SIZE` from environment (default 100, log warning if not a valid integer)
    - Instantiate `HistoryManager` with the same `s3Client`, `bucket`, `keyPrefix`, `maxHistorySize`, and `logger`
    - Replace existing `ISO8601DateFormatter().string(from: Date())` usage for `collectedAt` with `Date.now.formatted(.iso8601)`
    - _Requirements: 4.1, 4.2, 5.3_

  - [x] 3.3 Add `recordEntry` calls in both cache-hit and cache-miss paths
    - In the cache-hit branch, build artwork key via `S3Writer.buildKey(prefix:artist:title:file:)`, get timestamp via `Date.now.formatted(.iso8601)`, call `await historyManager.recordEntry(artist:title:artworkKey:timestamp:)`
    - In the cache-miss branch (after S3 writes), do the same `recordEntry` call
    - No do/catch needed — `recordEntry` is non-throwing
    - _Requirements: 2.1, 1.3, 1.4, 3.2, 5.2, 5.3_

- [x] 4. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests use Swift Testing parameterized `@Test` with 100+ random cases, matching the existing `S3WriterTests` pattern
- `appendAndTrim` is a static pure function specifically to enable property testing without S3 dependencies
- All history operations are non-fatal — errors are logged but never propagate
