# Requirements Document

## Introduction

The Lookup History feature adds a persistent history of recent song lookups to the existing IcecastMetadataCollector Lambda. Each time the Lambda processes a track (whether from S3 cache or a fresh Apple Music fetch), it appends an entry to a JSON history file stored in S3. The history file is designed for easy consumption by an iOS client app, containing artist, title, S3 artwork key, and a UTC timestamp of when the title was detected from the ICY stream. The history is capped at a configurable number of entries (default 100) controlled by an environment variable.

## Glossary

- **Collector_Lambda**: The existing `IcecastMetadataCollector` Lambda function that extracts Icecast stream metadata, searches Apple Music, and stores results in S3
- **History_Manager**: The new component responsible for reading, updating, and writing the lookup history JSON file in S3
- **History_File**: A JSON file stored at `<KEY_PREFIX>/history.json` in S3 containing an array of recent lookup entries under an `entries` key
- **History_Entry**: A single JSON object within the History_File representing one lookup, containing artist, title, S3 artwork key, and UTC timestamp
- **S3_Writer**: The existing component that handles all S3 read/write operations using `AWSS3.S3Client`
- **MAX_HISTORY_SIZE**: An environment variable specifying the maximum number of entries retained in the History_File (default: 100)

## Requirements

### Requirement 1: History File Structure

**User Story:** As an iOS client developer, I want the history file to have a well-defined JSON structure with an extensible wrapper object, so that I can easily parse it and the format can evolve over time.

#### Acceptance Criteria

1. THE History_File SHALL be a JSON object with a top-level key `entries` containing an array of History_Entry objects
2. Each History_Entry SHALL contain the following fields: `artist` (String), `title` (String), `artwork` (String containing the full S3 key to the artwork file), and `timestamp` (String in ISO 8601 UTC format)
3. THE History_Manager SHALL use the S3 artwork key as provided by the existing S3_Writer (S3 is the source of truth for key construction); the History_Manager SHALL NOT independently construct or assume the artwork key pattern
4. THE History_Manager SHALL format the `timestamp` field as an ISO 8601 string in UTC (e.g., `2025-01-15T14:30:00Z`) representing the time the title was detected from the ICY stream

### Requirement 2: History Entry Recording

**User Story:** As a radio station operator, I want every successful lookup to be recorded in the history, so that the iOS client always has an up-to-date list of recently played songs.

#### Acceptance Criteria

1. WHEN the Collector_Lambda has successfully identified a track (with valid artist and title), THE History_Manager SHALL add a new History_Entry to the History_File before the Lambda returns, regardless of whether the track data came from the S3 cache or from a fresh Apple Music fetch
2. WHEN a track is detected that has the same artist and title as an existing History_Entry, THE History_Manager SHALL add a new separate History_Entry rather than updating the existing entry
3. THE History_Manager SHALL append the new History_Entry to the entries array

### Requirement 3: History File Persistence

**User Story:** As a radio station operator, I want the history to be stored in S3 at a predictable location, so that the iOS client can reliably fetch it.

#### Acceptance Criteria

1. THE History_Manager SHALL store the History_File at the S3 key `<KEY_PREFIX>/history.json` in the bucket specified by the `S3_BUCKET` environment variable
2. WHEN the Collector_Lambda needs to update the history, THE History_Manager SHALL first read the existing History_File from S3, then add the new entry, then write the updated History_File back to S3
3. IF the History_File does not yet exist in S3 (first run), THEN THE History_Manager SHALL create a new History_File containing only the current entry

### Requirement 4: History Size Limit

**User Story:** As a developer, I want the history to be capped at a configurable maximum number of entries, so that the file size remains bounded and the iOS client does not download excessive data.

#### Acceptance Criteria

1. THE Collector_Lambda SHALL read the maximum history size from the `MAX_HISTORY_SIZE` environment variable
2. IF the `MAX_HISTORY_SIZE` environment variable is not set, THEN THE Collector_Lambda SHALL use a default value of 100
3. WHEN the number of entries in the History_File exceeds the value of `MAX_HISTORY_SIZE` after adding a new entry, THE History_Manager SHALL trim the entries array to retain only the most recent entries up to the `MAX_HISTORY_SIZE` limit
4. THE History_Manager SHALL remove the oldest entries (those at the beginning of the array) when trimming

### Requirement 5: Error Handling

**User Story:** As a developer, I want history file failures to be non-fatal, so that the main metadata collection pipeline is not disrupted by history-related issues.

#### Acceptance Criteria

1. IF reading the existing History_File from S3 fails for a reason other than the file not existing, THEN THE History_Manager SHALL log the error and proceed by creating a new History_File containing only the current entry
2. IF writing the updated History_File to S3 fails, THEN THE History_Manager SHALL log the error, and the Collector_Lambda SHALL continue to return successfully
3. THE History_Manager SHALL treat all history-related failures as non-fatal: the Collector_Lambda invocation SHALL succeed as long as the primary metadata collection pipeline completed successfully

### Requirement 6: Lambda Configuration

**User Story:** As a developer, I want the history size limit to be configurable via an environment variable in the SAM template, so that I can adjust it without code changes.

#### Acceptance Criteria

1. THE SAM_Template SHALL define the `MAX_HISTORY_SIZE` environment variable for the Collector_Lambda with a default value of `100`
2. THE SAM_Template SHALL grant the Collector_Lambda IAM permission to perform `s3:GetObject` on the S3 bucket, in addition to the existing `s3:PutObject` and `s3:HeadObject` permissions, so that the History_Manager can read the existing History_File

### Requirement 7: History File Round-Trip Integrity

**User Story:** As a developer, I want the history file to maintain data integrity through read-modify-write cycles, so that no entries are silently lost or corrupted.

#### Acceptance Criteria

1. FOR ALL valid History_File JSON content, reading the file, parsing it, serializing it back to JSON, and parsing again SHALL produce an equivalent set of History_Entry objects (round-trip property)
2. THE History_Manager SHALL use the same `JSONEncoder` and `JSONDecoder` configuration for all History_File serialization and deserialization operations
