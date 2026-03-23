# Icecast Metadata Collector — Algorithm

There are two Lambdas and a shared history file.

## Metadata Collection (IcecastMetadataCollector)

This Lambda runs on a schedule and captures what's currently playing on the Maxi 80 Icecast radio stream. Here's the pipeline:

1. Read raw metadata from the Icecast stream (the `ICY` protocol gives you a string like `"Artist - Title"`).
2. Parse it into `artist` and `title`. If both are empty, stop.
3. Read `history.json` from S3 and compare the current track against the most recent entry. If it's the same artist+title, the same song is still playing — bail out. This avoids redundant work when the Lambda fires multiple times during one track.
4. If the artist is `"maxi80"` / `"maxi 80"` (case-insensitive), it's station branding (jingles, promos). Record it in history with a `nocover.jpg` placeholder and stop — no point searching Apple Music for that.
5. Check the S3 cache: look for `{prefix}/{artist}/{title}/metadata.json`. If it exists, this track was already collected in a previous run. Record a history entry and stop.
6. Search Apple Music for `"{artist} {title}"`, pick the best match (preferring results that have artwork).
7. Upload three files to S3 under `{prefix}/{artist}/{title}/`: `metadata.json`, `search.json`, and `artwork.jpg` (when artwork exists). Record a history entry — the artwork key is `artwork.jpg` if artwork was downloaded, `nocover.jpg` otherwise.

## History Management

`HistoryManager` maintains a rolling `history.json` file in S3. When `recordEntry` is called, it reads the file, checks if the latest entry (by timestamp) already matches on artist, title, and artwork key. If so, it skips the write. Otherwise it appends the new entry and trims to a max size (default 100) by dropping the oldest. This is a second dedup layer on top of the early check in step 3 — a safety net at the write boundary.

## API Lambda (Maxi80Lambda)

The API Lambda exposes an `/artwork` endpoint. It doesn't talk to Apple Music at all — it just serves artwork that the collector already gathered:

- Takes `artist` and `title` query params
- Checks if `{prefix}/{artist}/{title}/artwork.jpg` exists in S3 via `HeadObject`
- If found, returns a JSON response with a pre-signed GET URL
- If not found, returns `204 No Content`

All Apple Music interaction is isolated in the collector. The API Lambda only needs S3 access.
