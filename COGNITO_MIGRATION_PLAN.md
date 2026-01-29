# Cognito Unauthenticated Access Migration Plan

## Overview
Migrate the Maxi80 Backend from API Key authentication to AWS Cognito Identity Pool with IAM-based SigV4 authentication. This enables secure, scalable access without managing API keys.

## Architecture Changes

### Before (Current)
```
iOS App → API Gateway (API Key) → Lambda → Apple Music API
```

### After (Target)
```
iOS App → Cognito Identity Pool (Temporary Credentials) → SigV4 Signer → API Gateway (IAM Auth) → Lambda → Apple Music API
```

## Implementation Tasks

### Phase 1: Infrastructure (SAM Template)

#### 1.1 Add Cognito Identity Pool
**File:** `template.yaml`

Add resources:
- `Maxi80IdentityPool`: Cognito Identity Pool with unauthenticated access enabled
- `Maxi80UnauthenticatedRole`: IAM role for unauthenticated users
- `Maxi80AuthenticatedRole`: IAM role for future authenticated users (optional)
- `IdentityPoolRoleAttachment`: Attach roles to identity pool

**IAM Policy for Unauthenticated Role:**
```yaml
- Effect: Allow
  Action: execute-api:Invoke
  Resource: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${ServerlessRestApi}/Prod/*"
```

#### 1.2 Modify API Gateway Configuration
**File:** `template.yaml`

Changes to `Maxi80Lambda.Events.ApiEvent`:
- Remove: `Auth.ApiKeyRequired: true`
- Add: `Auth.Authorizer: AWS_IAM`

Remove resources:
- `Maxi80ApiKey`
- `Maxi80UsagePlan`
- `Maxi80UsagePlanKey`

Add stage-level throttling settings:
```yaml
Globals:
  Api:
    MethodSettings:
      - ResourcePath: "/*"
        HttpMethod: "*"
        ThrottlingBurstLimit: 50
        ThrottlingRateLimit: 10
```

This applies the same throttling limits (burst: 50, rate: 10 req/sec) at the stage level instead of per API key.

#### 1.3 Update Outputs
**File:** `template.yaml`

Add outputs:
- `IdentityPoolId`: For iOS app configuration
- `Region`: For iOS app configuration

Remove outputs:
- `ApiKey`

---

### Phase 2: Swift Backend Code

#### 2.1 Add SigV4 Signer to Backend
**New File:** `Sources/Maxi80Backend/AWS/SigV4Signer.swift`

Copy from `cognito/SigV4Signer.swift` with modifications:
- Make it `public` for use in other modules
- Add comprehensive documentation
- Ensure compatibility with Swift 6 concurrency

#### 2.2 Use AWS SDK's Built-in Cognito Resolver
**No new file needed** - Use `CognitoAWSCredentialIdentityResolver` from AWS SDK

The AWS SDK provides `CognitoAWSCredentialIdentityResolver` which:
- Automatically handles `GetId` and `GetCredentialsForIdentity` operations
- Includes built-in credential caching with expiration checking
- Supports both authenticated and unauthenticated access via `logins` parameter
- Is an `actor` for thread-safe credential management

Usage example:
```swift
import AWSSDKIdentity

let resolver = try CognitoAWSCredentialIdentityResolver(
    identityPoolId: "us-east-1:xxxx-xxxx-xxxx",
    identityPoolRegion: "us-east-1"
)

// Get credentials (cached automatically)
let credentials = try await resolver.getIdentity(identityProperties: nil)

// Use with SigV4Signer
let signer = SigV4Signer(
    accessKey: credentials.accessKeyId,
    secretKey: credentials.secretAccessKey,
    sessionToken: credentials.sessionToken,
    region: "us-east-1"
)
```

For authenticated access (future enhancement):
```swift
// Update logins for authenticated users
await resolver.updateLogins(["cognito-idp.us-east-1.amazonaws.com/us-east-1_xxxxx": idToken])
```

#### 2.3 Update HTTP Client
**File:** `Sources/Maxi80Backend/HTTPClient/HTTPClient.swift`

**CRITICAL**: The HTTPClient must support SigV4 authentication for outbound API calls:

Add authentication strategy enum:
```swift
public enum AuthenticationMode {
    case none                                    // No authentication
    case sigV4(credentials: SigV4Credentials)    // AWS SigV4 signing
}

public struct SigV4Credentials {
    public let accessKey: String
    public let secretKey: String
    public let sessionToken: String?
    public let region: String
    public let service: String
}
```

Update `apiCall` method signature:
```swift
public func apiCall(
    url: URL,
    method: NIOHTTP1.HTTPMethod = .GET,
    body: Data? = nil,
    headers: [String: String] = [:],
    timeout: Int64 = 10,
    authentication: AuthenticationMode = .none  // NEW PARAMETER
) async throws -> (Data, HTTPClientResponse)
```

Implementation logic:
1. Build base request with standard headers
2. Apply authentication based on mode:
   - `.none`: No changes (used for Apple Music API calls)
   - `.sigV4(credentials)`: Sign request with SigV4Signer, add Authorization header
3. Execute request

**Why this matters:**
- CLI tool needs to call API Gateway with SigV4
- Future iOS app calls API Gateway with SigV4
- Backend Lambda calls Apple Music API with `.none` (no auth changes)

---

### Phase 3: CLI Tool Updates

#### 3.1 Update CLI for Testing
**File:** `Sources/Maxi80CLI/CLISearch.swift`

Add new command option:
```swift
@Flag(name: .long, help: "Use Cognito authentication instead of API key")
var useCognito: Bool = false

@Option(name: .long, help: "Cognito Identity Pool ID")
var identityPoolId: String?
```

Implement Cognito-based authentication flow for CLI testing.

#### 3.2 Add Cognito Test Command
**New File:** `Sources/Maxi80CLI/CLITestCognito.swift`

Create command to:
- Get credentials from Cognito Identity Pool
- Sign a test request
- Call the API
- Display results

---

### Phase 4: Documentation Updates

#### 4.1 Update README.md
**File:** `README.md`

Changes:
- Update architecture diagram
- Remove API key setup instructions
- Add Cognito setup instructions
- Update testing examples with SigV4 signing
- Add iOS integration code examples

#### 4.2 Update Makefile
**File:** `Makefile`

Replace:
```makefile
call-station:
	$(eval API_KEY := ...)
	curl -H "x-api-key: $(API_KEY)" ...
```

With:
```makefile
call-station:
	swift run Maxi80CLI --use-cognito --identity-pool-id $(IDENTITY_POOL_ID) station

call-search:
	swift run Maxi80CLI --use-cognito --identity-pool-id $(IDENTITY_POOL_ID) search "Pink Floyd"
```

Or implement a shell script that:
1. Gets Cognito credentials
2. Signs the request with SigV4
3. Calls the API with curl

#### 4.3 Create iOS Integration Guide
**New File:** `docs/iOS-Integration.md`

Document:
- How to add AWS SDK Swift to iOS project
- How to configure Cognito Identity Pool
- Complete code example for calling the API
- Error handling patterns
- Credential caching strategies

---

### Phase 5: Testing & Validation

#### 5.1 Unit Tests
**Files:** `Tests/Maxi80BackendTests/`

Add tests for:
- `SigV4SignerTests.swift`: Test signing logic
- `CognitoIdentityProviderTests.swift`: Test credential retrieval
- Mock Cognito responses

#### 5.2 Integration Tests
Create test script:
```bash
#!/bin/bash
# test-cognito-integration.sh

# 1. Deploy stack
make deploy

# 2. Get Identity Pool ID from outputs
IDENTITY_POOL_ID=$(aws cloudformation describe-stacks ...)

# 3. Test station endpoint
swift run Maxi80CLI --use-cognito --identity-pool-id $IDENTITY_POOL_ID station

# 4. Test search endpoint
swift run Maxi80CLI --use-cognito --identity-pool-id $IDENTITY_POOL_ID search "test"

# 5. Verify CloudWatch metrics
```

#### 5.3 Load Testing
Test throttling and quotas:
- Verify IAM policy restrictions work
- Test concurrent requests
- Verify CloudWatch alarms trigger correctly

---

### Phase 6: Deployment

#### 6.1 Deployment Steps
1. Deploy new stack with Cognito resources
2. Test with CLI tool
3. Update iOS app with new authentication
4. Monitor for errors

#### 6.2 Rollback Plan
- Keep previous SAM template version
- Document rollback command: `sam deploy --template-file template.yaml.backup`

---

### Phase 7: Per-Identity Rate Limiting (Optional Enhancement)

**Goal:** Add fine-grained rate limiting (2 requests/minute per Cognito Identity ID) with temporary blocking.

**Architecture Note:** The Lambda authorizer works in conjunction with IAM authentication:
1. Client sends SigV4-signed request to API Gateway
2. API Gateway validates IAM signature (Cognito credentials)  
3. API Gateway invokes Lambda authorizer with authenticated request context
4. Lambda authorizer extracts Cognito Identity ID and checks rate limit in DynamoDB
5. Lambda authorizer returns IAM policy (Allow/Deny)
6. If allowed, API Gateway forwards request to backend Lambda

This approach combines IAM authentication (handled by API Gateway) with custom rate limiting logic (handled by Lambda authorizer).

#### 7.1 DynamoDB Table for Rate Limiting
**File:** `template.yaml`

Add DynamoDB table resource:
```yaml
Maxi80RateLimitsTable:
  Type: AWS::DynamoDB::Table
  Properties:
    TableName: Maxi80-RateLimits
    BillingMode: PAY_PER_REQUEST
    AttributeDefinitions:
      - AttributeName: identityId
        AttributeType: S
    KeySchema:
      - AttributeName: identityId
        KeyType: HASH
    TimeToLiveSpecification:
      AttributeName: ttl
      Enabled: true
    Tags:
      - Key: Application
        Value: Maxi80Backend
```

**Table Schema:**
- `identityId` (String, Primary Key): Cognito Identity ID
- `tokens` (Number): Remaining tokens (capacity: 2)
- `lastRefill` (Number): Unix timestamp of last token refill
- `blockedUntil` (Number, Optional): Unix timestamp when block expires
- `ttl` (Number): Auto-cleanup timestamp (24 hours after last access)

#### 7.2 Lambda Authorizer Function
**New File:** `Sources/Maxi80Authorizer/Authorizer.swift`

Implement token bucket algorithm:
```swift
import AWSLambdaRuntime
import AWSLambdaEvents
import AWSDynamoDB
import Foundation

@main
struct Maxi80Authorizer: LambdaHandler {
    typealias Event = APIGatewayV2Request
    typealias Output = APIGatewayAuthorizerResponse
    
    private let dynamoDB: DynamoDBClient
    private let tableName: String
    
    // Rate limit configuration
    private let tokenCapacity: Double = 2.0
    private let refillRate: Double = 2.0 / 60.0  // 2 tokens per 60 seconds
    private let penaltyPeriod: TimeInterval = 300  // 5 minutes
    
    init() async throws {
        self.tableName = Lambda.env("RATE_LIMIT_TABLE") ?? "Maxi80-RateLimits"
        self.dynamoDB = try await DynamoDBClient()
    }
    
    func handle(_ event: Event, context: LambdaContext) async throws -> Output {
        // Extract Cognito Identity ID from request context
        guard let identityId = event.requestContext.identity?.cognitoIdentityId else {
            context.logger.error("No Cognito Identity ID in request")
            return denyPolicy(principalId: "unknown", message: "Unauthorized")
        }
        
        do {
            let allowed = try await checkRateLimit(identityId: identityId, context: context)
            
            if allowed {
                return allowPolicy(principalId: identityId, apiArn: event.requestContext.apiId)
            } else {
                context.logger.warning("Rate limit exceeded for identity: \(identityId)")
                return denyPolicy(principalId: identityId, message: "Rate limit exceeded")
            }
        } catch {
            context.logger.error("Rate limit check failed: \(error)")
            // Fail open - allow request if DynamoDB is unavailable
            return allowPolicy(principalId: identityId, apiArn: event.requestContext.apiId)
        }
    }
    
    private func checkRateLimit(identityId: String, context: LambdaContext) async throws -> Bool {
        let now = Date().timeIntervalSince1970
        
        // Get current rate limit state
        let item = try await getRateLimitItem(identityId: identityId)
        
        // Check if currently blocked
        if let blockedUntil = item?.blockedUntil, blockedUntil > now {
            return false
        }
        
        // Calculate tokens
        let lastRefill = item?.lastRefill ?? now
        let timeSinceRefill = now - lastRefill
        let tokensToAdd = timeSinceRefill * refillRate
        let currentTokens = min(tokenCapacity, (item?.tokens ?? tokenCapacity) + tokensToAdd)
        
        // Check if request can proceed
        if currentTokens >= 1.0 {
            // Allow request, consume token
            try await updateRateLimitItem(
                identityId: identityId,
                tokens: currentTokens - 1.0,
                lastRefill: now,
                blockedUntil: nil,
                ttl: Int(now) + 86400  // 24 hours
            )
            return true
        } else {
            // Block for penalty period
            let blockedUntil = now + penaltyPeriod
            try await updateRateLimitItem(
                identityId: identityId,
                tokens: 0,
                lastRefill: now,
                blockedUntil: blockedUntil,
                ttl: Int(blockedUntil) + 86400
            )
            return false
        }
    }
    
    private func getRateLimitItem(identityId: String) async throws -> RateLimitItem? {
        // DynamoDB GetItem implementation
        // ...
    }
    
    private func updateRateLimitItem(
        identityId: String,
        tokens: Double,
        lastRefill: TimeInterval,
        blockedUntil: TimeInterval?,
        ttl: Int
    ) async throws {
        // DynamoDB PutItem implementation with conditional write
        // ...
    }
    
    private func allowPolicy(principalId: String, apiArn: String) -> APIGatewayAuthorizerResponse {
        // Return IAM policy allowing access
        // ...
    }
    
    private func denyPolicy(principalId: String, message: String) -> APIGatewayAuthorizerResponse {
        // Return IAM policy denying access
        // ...
    }
}

struct RateLimitItem {
    let identityId: String
    let tokens: Double
    let lastRefill: TimeInterval
    let blockedUntil: TimeInterval?
    let ttl: Int
}
```

#### 7.3 Update API Gateway Configuration
**File:** `template.yaml`

Add Lambda authorizer:
```yaml
Maxi80Authorizer:
  Type: AWS::Serverless::Function
  Properties:
    Handler: bootstrap
    Runtime: provided.al2
    Architectures:
      - arm64
    CodeUri: .
    Environment:
      Variables:
        RATE_LIMIT_TABLE: !Ref Maxi80RateLimitsTable
    Policies:
      - DynamoDBCrudPolicy:
          TableName: !Ref Maxi80RateLimitsTable
  Metadata:
    BuildMethod: makefile

# Update API Gateway to use authorizer
Maxi80Lambda:
  Events:
    ApiEvent:
      Type: Api
      Properties:
        Path: /{proxy+}
        Method: ANY
        Auth:
          Authorizer: Maxi80CustomAuthorizer
          AuthorizationScopes: []

# Define the authorizer
Maxi80CustomAuthorizer:
  Type: AWS::ApiGateway::Authorizer
  Properties:
    Name: Maxi80RateLimitAuthorizer
    Type: REQUEST
    AuthorizerUri: !Sub "arn:aws:apigateway:${AWS::Region}:lambda:path/2015-03-31/functions/${Maxi80Authorizer.Arn}/invocations"
    AuthorizerResultTtlInSeconds: 0  # No caching for rate limiting
    IdentitySource: method.request.header.Authorization
    RestApiId: !Ref ServerlessRestApi

# Grant API Gateway permission to invoke authorizer
Maxi80AuthorizerPermission:
  Type: AWS::Lambda::Permission
  Properties:
    FunctionName: !Ref Maxi80Authorizer
    Action: lambda:InvokeFunction
    Principal: apigateway.amazonaws.com
    SourceArn: !Sub "arn:aws:execute-api:${AWS::Region}:${AWS::AccountId}:${ServerlessRestApi}/*"
```

#### 7.4 Monitoring and Alarms
**File:** `template.yaml`

Add CloudWatch alarms:
```yaml
RateLimitDenialAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: Maxi80-High-Rate-Limit-Denials
    AlarmDescription: Alert when many requests are being rate limited
    MetricName: Errors
    Namespace: AWS/Lambda
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 100
    ComparisonOperator: GreaterThanThreshold
    Dimensions:
      - Name: FunctionName
        Value: !Ref Maxi80Authorizer
    AlarmActions:
      - !Ref Maxi80AlertsTopic

DynamoDBThrottleAlarm:
  Type: AWS::CloudWatch::Alarm
  Properties:
    AlarmName: Maxi80-DynamoDB-Throttling
    AlarmDescription: Alert when DynamoDB is throttling requests
    MetricName: UserErrors
    Namespace: AWS/DynamoDB
    Statistic: Sum
    Period: 300
    EvaluationPeriods: 1
    Threshold: 10
    ComparisonOperator: GreaterThanThreshold
    Dimensions:
      - Name: TableName
        Value: !Ref Maxi80RateLimitsTable
    AlarmActions:
      - !Ref Maxi80AlertsTopic
```

#### 7.5 Testing Per-Identity Rate Limiting

**Test script:**
```bash
#!/bin/bash
# test-rate-limiting.sh

IDENTITY_POOL_ID="your-identity-pool-id"
API_URL="your-api-url"

# Get Cognito credentials
CREDENTIALS=$(aws cognito-identity get-credentials-for-identity ...)

# Make 3 requests rapidly (should block on 3rd)
for i in {1..3}; do
  echo "Request $i at $(date +%s)"
  # Sign and send request
  swift run Maxi80CLI --use-cognito station
  sleep 1
done

# Wait 30 seconds (1 token should refill)
echo "Waiting 30 seconds..."
sleep 30

# This should succeed
echo "Request after refill at $(date +%s)"
swift run Maxi80CLI --use-cognito station
```

#### 7.6 Configuration Parameters

Environment variables for authorizer:
- `RATE_LIMIT_TABLE`: DynamoDB table name
- `TOKEN_CAPACITY`: Maximum tokens (default: 2)
- `REFILL_RATE`: Tokens per second (default: 0.0333 = 2/60)
- `PENALTY_PERIOD`: Block duration in seconds (default: 300)
- `FAIL_OPEN`: Allow requests if DynamoDB fails (default: true)

#### 7.7 Cost Impact

**Additional monthly costs:**
- DynamoDB: ~$0.45 (10,000 requests/day)
- Lambda Authorizer: ~$0.02 (10,000 invocations/day)
- **Total: ~$0.50/month**

#### 7.8 Performance Impact

- Cold start: +100-200ms (first request)
- Warm requests: +10-20ms (DynamoDB read/write)
- Acceptable for non-real-time API

---

## File Changes Summary

### New Files
1. `Sources/Maxi80Backend/AWS/SigV4Signer.swift`
2. `Sources/Maxi80CLI/CLITestCognito.swift`
3. `docs/iOS-Integration.md`
4. `scripts/test-cognito-integration.sh`
5. `Tests/Maxi80BackendTests/SigV4SignerTests.swift`

### Modified Files
1. `template.yaml` - Major changes (Cognito resources, remove API key)
2. `README.md` - Update authentication documentation
3. `Makefile` - Update test commands
4. `Sources/Maxi80Backend/HTTPClient/HTTPClient.swift` - **CRITICAL: Add multi-mode authentication support**
5. `Sources/Maxi80CLI/CLISearch.swift` - Add Cognito option
6. `Sources/Maxi80CLI/GlobalOptions.swift` - Add Cognito flags
7. `Package.swift` - Add AWS SDK Cognito Identity dependency

### Removed Files
None (API key code can stay for reference)

---

## Dependencies to Add

**File:** `Package.swift`

Add to dependencies:
```swift
.package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "0.40.0")
```

Add to target dependencies:
```swift
// For Maxi80Backend target
.product(name: "AWSSDKIdentity", package: "aws-sdk-swift")

// For Maxi80CLI target  
.product(name: "AWSSDKIdentity", package: "aws-sdk-swift")
```

Note: `AWSSDKIdentity` includes `CognitoAWSCredentialIdentityResolver` and the internal Cognito Identity client.

---

## Security Considerations

1. **IAM Policies**: Least privilege - only allow specific API paths
2. **Rate Limiting**: Implement at API Gateway stage level
3. **Monitoring**: Enhanced CloudWatch alarms for unauthorized access
4. **Credential Rotation**: Cognito handles automatically (1-hour expiration)
5. **Identity Pool**: Disable authenticated access initially, enable later if needed

---

---

