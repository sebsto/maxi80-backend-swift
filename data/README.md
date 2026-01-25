# Data Processing Scripts

This directory contains metadata and results for processing radio station track information.

## Usage

### 1. Parse Metadata
Parses each line in `metadata.txt` using the metadata parsing function from the main library:

```bash
cd data/
swift run --package-path .. ParseMetadata
```

**Output:** Creates `search_results/` directory with numbered JSON files containing:
- `original`: Original metadata string
- `artist`: Parsed artist name (or null)
- `title`: Parsed title (or null)

### 2. Collect Apple Music Data
Searches Apple Music for each parsed track using the Maxi80CLI:

```bash
cd data/
swift run --package-path .. CollectAppleMusic
```

**Output:** Creates `apple_music_results/` directory with Apple Music API responses for each track.

**Requirements:**
- AWS profile `maxi80` configured
- Apple Music API credentials stored in AWS Secrets Manager
- Maxi80CLI built and available

## Files

- `metadata.txt`: Original radio station metadata (117 entries)
- `search_results/`: Parsed metadata JSON files
- `apple_music_results/`: Apple Music search results JSON files

## Benefits

- **No Code Duplication**: Scripts import `parseTrackMetadata()` directly from `Maxi80Backend`
- **Type Safety**: Uses the same data structures and parsing logic as the main application
- **Maintainability**: Changes to parsing logic automatically apply to scripts
