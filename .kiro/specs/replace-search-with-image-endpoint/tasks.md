# Implementation Plan: Replace Search with Artwork Endpoint

## Overview

Replace the `/search` Apple Music proxy endpoint with a `/artwork` endpoint that checks S3 for artwork existence and returns a pre-signed URL. This simplifies the Lambda by removing Apple Music dependencies and adding an S3 client. Tasks are ordered so foundational changes (endpoint enum, protocol, models) come first, followed by the action implementation, Lambda init refactor, template changes, and test updates.

## Tasks

- [x] 1. Update Endpoint enum and add S3ClientProtocol with ArtworkResponse model
  - [x] 1.1 Replace `.search` with `.artwork` in `Maxi80Endpoint` enum
    - In `Sources/Maxi80Backend/Endpoint.swift`, change `case search = "/search"` to `case artwork = "/artwork"`
    - The `from(path:)` static method requires no changes (it iterates `allCases`)
    - _Requirements: 1.3_

  - [x] 1.2 Add `S3ClientProtocol` to `Sources/Maxi80Lambda/Actions.swift`
    - Define `S3ClientProtocol` with `objectExists(bucket:key:)` and `presignedGetURL(bucket:key:expiration:)` methods
    - Both methods are `async throws`, protocol is `Sendable`
    - _Requirements: 4.4_

  - [x] 1.3 Add `AWSS3ClientAdapter` conforming to `S3ClientProtocol` in `Sources/Maxi80Lambda/Actions.swift`
    - Wrap `AWSS3.S3Client` for `headObject` and `presignGetObject`
    - `objectExists` returns `false` on `NotFound` error, `true` on success, rethrows other errors
    - _Requirements: 4.4, 6.1_

  - [x] 1.4 Add `ArtworkResponse` Codable struct in `Sources/Maxi80Lambda/Actions.swift`
    - Single `url: String` property, conforms to `Codable, Sendable`
    - _Requirements: 3.2_

- [x] 2. Implement ArtworkAction and remove SearchAction
  - [x] 2.1 Remove `SearchAction` struct from `Sources/Maxi80Lambda/Actions.swift`
    - Delete the entire `SearchAction` struct
    - _Requirements: 1.1_

  - [x] 2.2 Add `ArtworkAction` struct in `Sources/Maxi80Lambda/Actions.swift`
    - Conforms to `Action` protocol with `endpoint: .artwork`, `method: .get`
    - Init takes `s3Client: S3ClientProtocol`, `bucket: String`, `keyPrefix: String`, `urlExpiration: TimeInterval`, `logger: Logger`
    - `handle(event:)` extracts `artist` and `title` query params (throws `ActionError.missingParameter` if absent)
    - Builds S3 key as `"{keyPrefix}/{artist}/{title}/artwork.jpg"`
    - Calls `s3Client.objectExists`; if true, calls `presignedGetURL` and returns JSON-encoded `ArtworkResponse`; if false, returns empty `Data()`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.3_

  - [x] 2.3 Write property test: S3 key construction (Property 1)
    - **Property 1: S3 key construction**
    - For random non-empty artist/title strings, verify the S3 key passed to MockS3Client matches `"{keyPrefix}/{artist}/{title}/artwork.jpg"`
    - **Validates: Requirements 2.1, 3.3**

  - [x] 2.4 Write property test: Artwork exists returns JSON with pre-signed URL (Property 2)
    - **Property 2: Artwork exists returns JSON with pre-signed URL**
    - For random artist/title with mock returning exists=true, verify response decodes to `ArtworkResponse` with non-empty `url`
    - **Validates: Requirements 2.2, 3.1, 3.2**

  - [x] 2.5 Write property test: Artwork not found returns empty response (Property 3)
    - **Property 3: Artwork not found returns empty response**
    - For random artist/title with mock returning exists=false, verify response is empty `Data`
    - **Validates: Requirements 2.3, 3.5**

  - [x] 2.6 Write property test: Pre-signed URL uses configured expiration (Property 4)
    - **Property 4: Pre-signed URL uses configured expiration**
    - For random positive expiration values, verify the mock receives the correct expiration
    - **Validates: Requirements 3.4**

  - [x] 2.7 Write property test: S3 errors propagate (Property 7)
    - **Property 7: S3 errors propagate as internal server error**
    - For random non-NotFound S3 errors, verify ArtworkAction throws
    - **Validates: Requirements 6.1**

- [x] 3. Checkpoint
  - Ensure all tests pass, ask the user if questions arise.

- [x] 4. Refactor Lambda initialization and handle method
  - [x] 4.1 Simplify `Maxi80Lambda.init` in `Sources/Maxi80Lambda/Lambda.swift`
    - Change init signature to `init(s3Client: S3ClientProtocol? = nil, logger: Logger? = nil) async throws`
    - Remove `musicAPIClient`, `tokenFactory` parameters
    - Remove HTTPClient, SecretsManager, AppleMusicAuthProvider creation
    - Read `S3_BUCKET`, `KEY_PREFIX` (default `"v2"`), `URL_EXPIRATION` (default `3600`) from environment
    - Create `AWSS3ClientAdapter` if no mock `s3Client` is injected
    - Register `[StationAction, ArtworkAction]` with the Router
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6_

  - [x] 4.2 Update `handle` method in `Sources/Maxi80Lambda/Lambda.swift`
    - After `action.handle(event:)`, check if `responseData.isEmpty`
    - If empty: return `APIGatewayResponse(statusCode: .noContent)` with no body and no content-type header
    - If non-empty: return 200 with `application/json` content-type and the JSON body
    - _Requirements: 2.3, 3.1, 3.5_

  - [x] 4.3 Clean up `Sources/Maxi80Lambda/LambdaError.swift`
    - Remove `cantAccessMusicAPISecret` and `noAuthenticationToken` cases (no longer used)
    - If no cases remain, remove the enum or leave it empty for future use
    - _Requirements: 4.1, 4.2, 4.3_

- [x] 5. Update SAM template
  - [x] 5.1 Update `template.yaml` Maxi80Lambda environment variables
    - Remove `SECRETS` env var from Maxi80Lambda
    - Add `S3_BUCKET: !Ref MetadataBucket`
    - Add `KEY_PREFIX: v2`
    - Add `URL_EXPIRATION: 3600`
    - Do NOT modify IcecastMetadataCollector env vars
    - _Requirements: 7.3, 7.4, 7.5, 7.6_

  - [x] 5.2 Update `template.yaml` Maxi80Lambda IAM policies
    - Remove SecretsManager policy from Maxi80Lambda only
    - Add S3 policy granting `s3:GetObject` and `s3:HeadObject` on `!Sub "arn:aws:s3:::${MetadataBucket}/*"`
    - Do NOT modify IcecastMetadataCollector policies
    - _Requirements: 7.1, 7.2, 7.7_

- [x] 6. Create MockS3Client and update tests
  - [x] 6.1 Create `MockS3Client` in `Tests/Maxi80BackendTests/Mocks/MockS3Client.swift`
    - Follow existing `MockHTTPClient` pattern: `final class MockS3Client: S3ClientProtocol, @unchecked Sendable`
    - Track call records (bucket, key), presign expirations
    - Support configuring exists results, presigned URLs, and errors
    - _Requirements: 4.4_

  - [x] 6.2 Update `Tests/Maxi80BackendTests/RouterTests.swift`
    - Replace all references to `SearchAction` and `.search` with `ArtworkAction` and `.artwork`
    - Update endpoint raw value tests: `.artwork` has rawValue `/artwork`
    - Add test for ArtworkAction properties (endpoint, method)
    - Add test for ArtworkAction missing `artist` parameter
    - Add test for ArtworkAction missing `title` parameter
    - Add test for ArtworkAction successful artwork lookup (mock returns exists + presigned URL)
    - Add test for ArtworkAction artwork not found (mock returns not exists, verify empty Data)
    - Remove `MockAuthProvider` if no longer needed
    - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4, 2.5, 5.1, 5.4, 5.5_

  - [x] 6.3 Update `Tests/Maxi80BackendTests/LambdaHandlerTests.swift`
    - Update Lambda initialization test to use `Maxi80Lambda(s3Client: mockS3Client, logger: logger)`
    - Remove tests referencing `SearchAction`, `/search`, `musicAPIClient`, `tokenFactory`
    - Add test verifying Lambda init no longer requires HTTPClient or SecretsManager
    - Update station endpoint test to use new init signature
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 5.1_

  - [x] 6.4 Write property test: Unrecognized paths return path-not-found (Property 5)
    - **Property 5: Unrecognized paths return path-not-found**
    - For random path strings that are not `/station` or `/artwork`, verify Router returns `.pathNotFound`
    - **Validates: Requirements 5.4**

  - [x] 6.5 Write property test: Unsupported methods return method-not-allowed (Property 6)
    - **Property 6: Unsupported methods return method-not-allowed**
    - For random non-GET HTTP methods on `/artwork` and `/station`, verify Router returns `.methodNotAllowed`
    - **Validates: Requirements 5.5**

- [x] 7. Final checkpoint
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Post-audit cleanup: MockS3Client thread safety
  - [x] 8.1 Convert `MockS3Client` from `final class` to `actor` in `Tests/Maxi80BackendTests/Mocks/MockS3Client.swift`
    - Remove `@unchecked Sendable` conformance (actors are implicitly Sendable)
    - All mutable state (`existsResults`, `presignedURLs`, `errors`, `callRecords`, `presignExpirations`, `currentIndex`) is protected by actor isolation
    - All call sites are already `async`, so no caller changes needed beyond adding `await` to test helper calls (`setExists`, `setPresignedURL`, `setError`, `getCallRecords`, `getPresignExpirations`, `reset`)
    - Update `RouterTests.swift`, `LambdaHandlerTests.swift`, `ArtworkActionPropertyTests.swift`, and `RouterPropertyTests.swift` to `await` mock helper calls
    - _Audit finding: `@unchecked Sendable` with unprotected mutable state violates the Sendable contract_

- [x] 9. Post-audit cleanup: MockS3Client index coupling
  - [x] 9.1 Decouple `objectExists` and `presignedGetURL` response queues in `MockS3Client`
    - Add a separate `presignIndex` counter for `presignedGetURL` instead of relying on `currentIndex - 1`
    - `objectExists` uses `currentIndex` for `existsResults` and `errors`
    - `presignedGetURL` uses `presignIndex` for `presignedURLs`
    - This removes the implicit contract that `presignedGetURL` must be called immediately after `objectExists`
    - Update `reset()` to also reset `presignIndex`
    - _Audit finding: shared `currentIndex` across two methods is fragile and breaks if methods are called independently_

- [x] 10. Post-audit cleanup: Remove dead code
  - [x] 10.1 Delete `Sources/Maxi80Lambda/LambdaError.swift`
    - The `LambdaError` enum contains only `missingConfiguration(name:)` which is no longer thrown anywhere after the Lambda init refactor
    - Remove the file entirely
    - Remove any import references if they exist
    - _Audit finding: `LambdaError` is dead code after removing SecretsManager/AppleMusic dependencies_

  - [x] 10.2 Remove the deleted `Sources/Maxi80Backend/AWS/S3Cache.swift` from git tracking
    - The file is already deleted in the working tree (entirely commented-out placeholder code)
    - Ensure it is staged for deletion in the commit
    - _Audit finding: file was entirely commented-out placeholder code_

- [x] 11. Post-audit cleanup: Document `@unchecked Sendable` on AWSS3ClientAdapter
  - [x] 11.1 Add a safety invariant comment to `AWSS3ClientAdapter` in `Sources/Maxi80Lambda/Actions.swift`
    - Add a comment above the struct explaining why `@unchecked Sendable` is needed (the AWS SDK `S3Client` type is not yet `Sendable`-annotated)
    - Add a `// TODO:` to remove `@unchecked Sendable` once the AWS SDK for Swift marks `S3Client` as `Sendable`
    - _Audit finding: Swift concurrency guidelines require documented safety invariants for `@unchecked Sendable`_

- [x] 12. Final verification
  - Build the project with `swift build` and run all tests with `swift test` to confirm no regressions.

## Notes

- Tasks 1–7 implement the core feature (all complete)
- Tasks 8–12 address post-audit cleanup findings
- Each task references the specific audit finding it resolves
- Use Swift Testing framework (`@Test`, `#expect`, `@Suite`) for all tests — not XCTest
- Follow existing `MockHTTPClient` pattern for `MockS3Client`
- When converting `MockS3Client` to an actor, the `S3ClientProtocol` conformance works because the protocol methods are already `async`
