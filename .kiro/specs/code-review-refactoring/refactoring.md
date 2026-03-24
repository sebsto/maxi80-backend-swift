# Code Review Refactoring Spec

## Overview

This document captures all findings from a full codebase review of the Maxi80 backend project. Each finding includes the affected files, a description of the problem, the expected fix, and priority. An implementing agent should work through these in priority order.

## Convention: Error Types in Public APIs

**Project convention (applies to all findings below):** Error types that are part of the `Maxi80Backend` public API must NOT be public enums. Public enums are exhaustive — adding a case is a source-breaking change for any client with a `switch`. Instead, use a struct with a private backing enum and static factory properties:

```swift
public struct SomeError: Error, CustomStringConvertible {
    private enum Code {
        case somethingFailed(reason: String)
    }

    private let code: Code

    public var description: String {
        switch code {
        case .somethingFailed(let reason): return "Something failed: \(reason)"
        }
    }

    public static func somethingFailed(reason: String) -> Self {
        .init(code: .somethingFailed(reason: reason))
    }
}
```

Error enums that are `internal` (not part of the public API) are fine as-is — no change needed for those.

---

## Priority 1: Security / Robustness

### Finding 2: SecretsManager.getSecret swallows the underlying AWS SDK error

**File:** `Sources/Maxi80Backend/AWS/SecretsManager.swift`

**Problem:** The `getSecret` method uses `try?` to call the AWS SDK, discarding the actual error:

```swift
guard let response = try? await self.smClient.getSecretValue(input: request) else {
    throw SecretsManagerError.invalidResponse(reason: "Error calling SecretsManager client...")
}
```

The real root cause (IAM permission denied, throttling, network timeout, etc.) is lost. The replacement error message is a generic suggestion to check permissions, which is unhelpful when the actual problem is something else entirely.

**Fix:** Replace `try?` with a `do/catch` block. Catch the AWS SDK error and wrap it in `SecretsManagerError.backendError(rootcause:)` (or a new case that preserves the original error). The error message logged to CloudWatch should include the original error's description.

```swift
let response: GetSecretValueOutput
do {
    response = try await self.smClient.getSecretValue(input: request)
} catch {
    throw SecretsManagerError.backendError(rootcause: error)
}
```

---

### Finding 3: SecretsManager.storeSecret force-unwraps String encoding

**File:** `Sources/Maxi80Backend/AWS/SecretsManager.swift`

**Problem:** In `storeSecret`, the JSON-encoded data is force-unwrapped when converting to a UTF-8 string:

```swift
let secretString = String(data: data, encoding: .utf8)!
```

If `JSONEncoder` ever produces non-UTF-8 output (extremely unlikely but not impossible with custom encoders), this crashes the Lambda process.

**Fix:** Replace with a `guard let` and throw a `SecretsManagerError.decodingFailed` on failure:

```swift
guard let secretString = String(data: data, encoding: .utf8) else {
    throw SecretsManagerError.decodingFailed(reason: "Failed to encode secret as UTF-8 string")
}
```

---

## Priority 2: Robustness / Correctness

### Finding 6: MockHTTPClient makes real network calls

**File:** `Tests/Maxi80BackendTests/Mocks/MockHTTPClient.swift`

**Problem:** The `apiCall` method in `MockHTTPClient` makes a real HTTP request to `https://httpbin.org/status/200` to obtain an `HTTPClientResponse` object:

```swift
let client = HTTPClient.shared
let testRequest = HTTPClientRequest(url: "https://httpbin.org/status/200")
let response = try await client.execute(testRequest, timeout: .seconds(1))
return (data, response)
```

This means any test using `MockHTTPClient` requires internet access and is inherently flaky (DNS failures, httpbin.org downtime, CI network restrictions, timeouts).

**Fix:** The mock should not make any network calls. The `HTTPClientProtocol` returns `(Data, HTTPClientResponse)`. Since `HTTPClientResponse` cannot be easily constructed directly, consider one of these approaches:

1. Change `HTTPClientProtocol` to return `(Data, HTTPResponseStatus)` instead of `(Data, HTTPClientResponse)`, since callers only check `response.status` anyway. This is the cleanest fix but requires updating all call sites.
2. If `HTTPClientResponse` must be preserved, create a minimal test helper that constructs one without network I/O (check if the type has any public initializers in the AsyncHTTPClient API).
3. As a last resort, return just the `Data` from the mock and adjust the protocol to make the response metadata optional or separate.

The implementing agent should check the `HTTPClientResponse` API to determine which approach is feasible.

---

### Finding 8: Region rejects unknown AWS regions

**File:** `Sources/Maxi80Backend/AWS/Region.swift`

**Problem:** `Region.init?(awsRegionName:)` has a hardcoded allowlist of known regions. Any new AWS region (e.g., `il-central-1`, `ap-southeast-5`, `ap-southeast-7`) returns `nil`, silently failing. The `Region` struct itself accepts any string via `init(rawValue:)`, but the failable initializer rejects anything not in the list.

**Fix:** Two options (implementing agent should choose based on project preference):

**Option A (recommended):** Accept any well-formed region string. Add a regex or simple validation (`^[a-z]{2}-[a-z]+-\d+$`) and accept it. Keep the static properties for convenience but don't reject unknown regions.

**Option B (minimal):** Remove the failable initializer entirely. Callers already use `Region(rawValue:)` in most places. The failable initializer is only used in `Lambda.env("AWS_REGION").flatMap { Region(awsRegionName: $0) }` — replace with `Region(rawValue:)` directly.

---

### Finding 9: MetadataParser uses bare Foundation import

**File:** `Sources/Maxi80Backend/MetadataParser.swift`

**Problem:** This file uses `import Foundation` without the conditional `FoundationEssentials` pattern that every other file in the project follows:

```swift
import Foundation  // Should use the conditional pattern
```

Every other file in the project uses:
```swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
```

**Fix:** Replace `import Foundation` with the conditional import pattern. The file only uses `CharacterSet` (via `trimmingCharacters(in:)`) and `String` APIs, which are available in `FoundationEssentials`.

---

### Finding 10: TrackMetadata is not Sendable

**File:** `Sources/Maxi80Backend/MetadataParser.swift`

**Problem:** `TrackMetadata` is a struct with two `String?` properties but does not conform to `Sendable`. It is used across async boundaries — parsed in one context and consumed in another (e.g., in `IcecastMetadataCollector/Lambda.swift`). Under Swift 6 strict concurrency, this will produce warnings or errors.

**Fix:** Add `Sendable` conformance. Since it's a struct with only `String?` stored properties, conformance is automatic:

```swift
public struct TrackMetadata: Sendable {
    public let artist: String?
    public let title: String?
    // ...
}
```

---

## Priority 3: Maintainability / Code Quality

### Finding 11: TokenCache actor uses confusing overloaded method names

**File:** `Sources/Maxi80Backend/AppleMusic/AppleMusicAuthProvider.swift`

**Problem:** The nested `TokenCache` actor uses overloaded method names for get and set:

```swift
actor TokenCache {
    var authTokenString: String? = nil
    func token(_ token: String) async {       // setter
        self.authTokenString = token
    }
    func token() async -> String? {           // getter
        self.authTokenString
    }
}
```

Reading `await self.tokenCache.token()` vs `await self.tokenCache.token(token)` is confusing — both look like getters at a glance.

**Fix:** Rename to explicit `setToken(_:)` and `getToken()`:

```swift
actor TokenCache {
    private var authTokenString: String? = nil
    func setToken(_ token: String) {
        self.authTokenString = token
    }
    func getToken() -> String? {
        self.authTokenString
    }
}
```

Update the two call sites in `AppleMusicAuthProvider.authorizationHeader(logger:)` accordingly.

---

### Finding 12: Typo in HTTPLogger

**File:** `Sources/Maxi80Backend/HTTPClient/HTTPLogger.swift`

**Problem:** The response logging header contains a typo:

```swift
self.trace("\n - - - - - - - - - - INCOMMING - - - - - - - - - - \n")
```

**Fix:** Change `INCOMMING` to `INCOMING`.

---

### Finding 13: MusicAPIClient response body collection fails on missing content-length

**File:** `Sources/Maxi80Backend/HTTPClient/HTTPClient.swift`

**Problem:** The `apiCall` method tries to read `content-length` from the response headers and uses it to size the body collection:

```swift
guard let responseSize = Int(response.headers.first(name: "content-length") ?? ""),
    let bytes = try? await response.body.collect(upTo: max(responseSize, 1024 * 1024 * 10))
else {
    logger.debug("No readable bytes in the response")
    throw HTTPClientError.zeroByteResource
}
```

If the `content-length` header is missing (which is common for chunked transfer encoding), `Int("")` returns `nil`, the entire `guard` fails, and the method throws `zeroByteResource` even though the response body has valid data.

**Fix:** Default to the 10MB cap when `content-length` is missing:

```swift
let maxSize = Int(response.headers.first(name: "content-length") ?? "") ?? (10 * 1024 * 1024)
guard let bytes = try? await response.body.collect(upTo: max(maxSize, 10 * 1024 * 1024)) else {
    logger.debug("No readable bytes in the response")
    throw HTTPClientError.zeroByteResource
}
```

---

### Finding 14: CollectAppleMusic shell command injection risk

**File:** `Sources/CollectAppleMusic/main.swift`

**Problem:** The script constructs shell commands via string interpolation with metadata that comes from external input (the `metadata.txt` file):

```swift
let escapedQuery = searchQuery.replacingOccurrences(of: "\"", with: "\\\"")
let command = "swift run Maxi80CLI --profile maxi80 --region eu-central-1 search --types songs \"\(escapedQuery)\""
let result = runCommand(command)
```

The escaping only handles double quotes. Metadata strings containing `$()`, backticks, semicolons, or other shell metacharacters could cause unintended command execution.

**Fix:** Instead of shelling out via `/bin/bash -c`, use `Process` with an explicit arguments array, which avoids shell interpretation entirely:

```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
process.arguments = ["run", "Maxi80CLI", "--profile", "maxi80", "--region", "eu-central-1", "search", "--types", "songs", searchQuery]
```

This passes `searchQuery` as a single argument with no shell interpretation.

---

### Finding 15: Maxi80APIClient is a class with no mutable state

**File:** `Sources/Maxi80Backend/Maxi80APIClient.swift`

**Problem:** `Maxi80APIClient` is declared as `public class` but has no mutable state after initialization (`baseURL`, `apiKey`, and `session` are all `let` properties). It also does not conform to `Sendable`, which will cause warnings under strict concurrency when passed across isolation boundaries.

**Fix:** Change from `class` to `struct` and add `Sendable` conformance. The `session` property uses `URLSessionProtocol` which is not `Sendable` — either:
- Mark `URLSessionProtocol` as `Sendable` (if all conforming types are thread-safe, which `URLSession.shared` is), or
- ~~Use `@unchecked Sendable` with a documented safety invariant (same pattern as `S3Manager`).~~ NEVER introduce new unchecked sendable

---

### Finding 17: S3Writer and HistoryManager duplicate configuration

**Files:** `Sources/IcecastMetadataCollector/S3Writer.swift`, `Sources/IcecastMetadataCollector/HistoryManager.swift`, `Sources/IcecastMetadataCollector/Lambda.swift`

**Problem:** Both `S3Writer` and `HistoryManager` store the same three properties: `s3Client`, `bucket`, `keyPrefix`. They are initialized with identical values in `Lambda.swift`:

```swift
self.s3Writer = S3Writer(s3Client: s3Client, bucket: bucket, keyPrefix: keyPrefix)
self.historyManager = HistoryManager(s3Client: s3Client, bucket: bucket, keyPrefix: keyPrefix, maxHistorySize: maxHistorySize)
```

**Fix:** Extract a shared `S3Config` struct:

```swift
struct S3Config {
    let s3Client: S3ManagerProtocol
    let bucket: String
    let keyPrefix: String
}
```

Then `S3Writer` and `HistoryManager` each take an `S3Config` instead of three separate parameters. This reduces duplication and makes it impossible to accidentally pass different bucket/prefix values to the two components.

---

## Priority 4: Minor / Cosmetic

### Finding 5: Stale Makefile target

**File:** `Makefile`

**Problem:** The `call-search` target curls the Lambda's `/search` endpoint, which was removed and replaced by `/artwork`. This target will always return a 404.

**Fix:** Either remove the `call-search` target or replace it with a `call-artwork` target that calls the `/artwork` endpoint with sample `artist` and `title` query parameters.

---

### Finding 18: AppleMusicEndpoint.test case is dev-only

**File:** `Sources/Maxi80Backend/AppleMusic/AppleMusic.swift`

**Problem:** The `.test` case in `AppleMusicEndpoint` exists only for development/testing purposes but is compiled into production builds.

**Fix:** Gate it behind `#if DEBUG`:

```swift
public enum AppleMusicEndpoint: String, CaseIterable, Sendable {
    #if DEBUG
    case test = "/test"
    #endif
    case search = "/catalog/fr/search"
    // ...
}
```

Note: this may require adjusting `AppleMusicTests.swift` which references `.test`. The test target compiles with DEBUG by default, so it should still work.

---

### Finding 19: Error enums lack descriptive conformances

**Files:** `Sources/IcecastMetadataCollector/Errors.swift`, `Sources/Maxi80Backend/HTTPClient/HTTPClient.swift`

**Problem:** `IcecastError`, `CollectorError`, and `HTTPClientError` don't conform to `CustomStringConvertible` or `LocalizedError`. When these errors are logged via `error.localizedDescription`, the output is a generic Swift error description rather than a human-readable message.

**Fix:** Add `CustomStringConvertible` conformance with meaningful descriptions. These are all internal types (not part of the public API), so enums are fine here — no need for the struct pattern.

Example for `IcecastError`:

```swift
enum IcecastError: Error, CustomStringConvertible {
    case connectionFailed(reason: String)
    case missingMetaInt
    case timeout
    case noMetadata
    case invalidStreamTitle

    var description: String {
        switch self {
        case .connectionFailed(let reason): return "Icecast connection failed: \(reason)"
        case .missingMetaInt: return "Icecast server response missing icy-metaint header"
        case .timeout: return "Icecast stream reading timed out"
        case .noMetadata: return "No metadata found in Icecast stream"
        case .invalidStreamTitle: return "Invalid StreamTitle format in Icecast metadata"
        }
    }
}
```

Apply the same pattern to `CollectorError` and `HTTPClientError`.

---

### Finding 20: ParseMetadata uses hardcoded file paths

**File:** `Sources/ParseMetadata/main.swift`

**Problem:** The script uses hardcoded paths `"metadata.txt"` and `"search_results"`. It only works when run from the project root directory.

**Fix:** Accept file paths as command-line arguments with sensible defaults:

```swift
let metadataFile = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "metadata.txt"
let outputDir = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "search_results"
```

---

### Finding 21: Duplicate `from(path:)` implementations

**Files:** `Sources/Maxi80Backend/Endpoint.swift`, `Sources/Maxi80Backend/AppleMusic/AppleMusic.swift`

**Problem:** Both `Maxi80Endpoint` and `AppleMusicEndpoint` have identical `from(path:)` static methods:

```swift
public static func from(path: String) -> Self? {
    self.allCases.first { $0.rawValue == path }
}
```

**Fix:** Extract into a protocol extension:

```swift
public protocol PathMatchable: RawRepresentable, CaseIterable where RawValue == String {
    static func from(path: String) -> Self?
}

extension PathMatchable {
    public static func from(path: String) -> Self? {
        allCases.first { $0.rawValue == path }
    }
}
```

Then conform both enums: `Maxi80Endpoint: PathMatchable` and `AppleMusicEndpoint: PathMatchable`, removing the manual `from(path:)` implementations.

---

## Implementation Order

The implementing agent should work through these in the following order to minimize merge conflicts and ensure each change is independently testable:

1. Finding 2 (SecretsManager error swallowing) — security fix, no API change
2. Finding 3 (force-unwrap) — safety fix, no API change
3. Finding 10 (TrackMetadata Sendable) — one-line addition
4. Finding 9 (MetadataParser conditional import) — one-line change
5. Finding 12 (typo fix) — one-line change
6. Finding 11 (TokenCache rename) — small refactor, 3 files
7. Finding 13 (content-length fallback) — small logic fix
8. Finding 19 (error descriptions) — additive, no API change
9. Finding 15 (Maxi80APIClient class→struct) — moderate refactor
10. Finding 17 (S3Config extraction) — moderate refactor
11. Finding 6 (MockHTTPClient network calls) — test infrastructure
12. Finding 8 (Region validation) — behavior change, needs care
13. Finding 14 (shell injection) — utility script fix
14. Finding 21 (PathMatchable protocol) — cosmetic refactor
15. Finding 5 (Makefile cleanup) — trivial
16. Finding 18 (DEBUG gate) — trivial
17. Finding 20 (hardcoded paths) — trivial

After each change, run `swift test` to verify nothing breaks.
