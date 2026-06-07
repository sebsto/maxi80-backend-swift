# Maxi80 Backend — Cost Analysis (June 7, 2026)

## Monthly Cost Breakdown (May 2025)

| Service | Monthly Cost | % of Total |
|---------|-------------|-----------|
| **S3 Storage (Standard-IA)** | $5.11 | **73%** |
| **S3 Requests (PUT/POST Tier 1)** | $0.19 | 3% |
| **S3 Requests (GET Tier 2)** | $0.06 | <1% |
| **S3 Storage (Standard)** | $0.06 | <1% |
| **AWS AppSync** | $0.23 | 3% |
| **AWS CloudTrail** | $0.18 | 3% |
| **CloudWatch** | $0.13 | 2% |
| **S3 Data Transfer (EU→US-EAST-1)** | $0.03 | <1% |
| **AWS Lambda** | $0.00 | 0% (free tier) |
| **SNS** | $0.00 | 0% (free tier) |
| **Tax** | $1.20 | — |
| **Total** | **~$7.19** | |

## Key Finding: S3 Standard-IA Storage is 73% of Total Cost

The dominant cost is **409 GB of S3 Standard-Infrequent Access storage at $5.11/month**.

### Where is this 409 GB?

The visible bucket contents account for far less:
- `artwork.maxi80.com`: 2.6 GB Standard (artwork, metadata, history)
- `logs.maxi80.com`: 2.3 GB Standard (currently empty listing but CloudWatch shows 2.3 GB)
- `alexa.maxi80.com`: 28 MB Standard + 0.5 MB Reduced Redundancy
- SAM buckets: ~450 MB Standard

**The 409 GB S3-IA charge does not correspond to any visible objects in Standard-IA storage class.** This likely means:
1. The data was recently transitioned or deleted but was billed for the full month, or
2. There is S3 Inventory / S3 Storage Lens overhead being reported under this usage type, or
3. A previous lifecycle transition moved data to IA that has since been deleted (S3-IA has a 30-day minimum storage charge)

**Action: Investigate what generated this 409 GB S3-IA charge.** Check AWS billing console → Cost Explorer → group by resource (requires Cost Allocation Tags or S3 Storage Lens).

---

## The `logs.maxi80.com` Bucket — 2.3 GB of Hidden Storage

CloudWatch metrics show this bucket holds **2.3 GB** of Standard storage, yet `aws s3 ls --recursive` shows 0 objects. This suggests:
- Objects may be stored with versioning enabled (non-current versions invisible to normal listing)
- Or the bucket is receiving CloudFront/S3 access logs that were recently purged
- Or there's a delete marker issue

**Cost impact:** 2.3 GB Standard = ~$0.053/month (negligible). But worth understanding.

---

## Ranked Cost Reduction Opportunities

### 1. Eliminate or Reduce the 409 GB S3-IA Charge — Save up to $5.11/month (73% of bill)

**Priority: HIGH — This is the single most impactful change.**

This charge is the vast majority of your bill. Steps to investigate and fix:
- Enable S3 Storage Lens (free dashboard tier) to identify which bucket holds this data
- Check if a lifecycle rule previously transitioned data to S3-IA in another bucket or prefix
- If the data is no longer needed, delete it — but note S3-IA has a 30-day minimum charge per object
- If it IS needed and rarely accessed, consider moving to **S3 Glacier Instant Retrieval** ($0.004/GB/month vs $0.0125/GB/month for IA) — would reduce this from $5.11 to ~$1.64/month

### 2. Clean Up SAM Deployment Artifacts — Save ~$0.01/month + reduce clutter

The SAM source bucket (`u2e0hlyfnacm`) has **6 old deployment zips** (~65 MB each = 390 MB total). Only the latest is needed. 

```bash
# Keep only the latest, delete old deployment artifacts
aws s3 rm s3://aws-sam-cli-managed-default-samclisourcebucket-u2e0hlyfnacm/Maxi80Backend-2025/ \
  --recursive --exclude "Maxi80Lambda-latest.zip" --exclude "*.template" \
  --profile maxi80 --region eu-west-1
```

Minimal cost savings but good hygiene.

### 3. Delete `v1/` Prefix in artwork.maxi80.com — Save ~$0.009/month

The `v1/` prefix contains **6,282 objects / 394 MB** from the old format (just `info.json` + `cover.png`). If the iOS app has fully migrated to `v2/`, this can be deleted.

**Savings:** Negligible in storage ($0.009/month) but reduces S3 GET request costs if any legacy requests still hit `v1/`.

### 4. Reduce IcecastMetadataCollector Schedule — Save on S3 PUT Requests

Currently running every 2 minutes = **21,600 invocations/month**. In May, S3 saw **38,432 Tier-1 (PUT) requests** costing $0.19.

Increasing the schedule from `rate(2 minutes)` to `rate(5 minutes)` would reduce PUT requests by ~60%:
- **Savings:** ~$0.11/month on S3 PUTs
- **Lambda:** Already at $0.00 (free tier), so no Lambda savings

### 5. Lambda Costs — Already $0.00 (Optimized)

Both Lambda functions are fully covered by the free tier (1M requests + 400,000 GB-seconds/month). Memory has been **reduced from 256 MB to 128 MB** (June 7, 2026) based on actual usage analysis:

| Lambda | Peak Memory Used | Configured Memory | Utilization |
|--------|-----------------|-------------------|-------------|
| IcecastMetadataCollector | 92 MB | 128 MB | 72% |
| Maxi80Lambda | 84 MB | 128 MB | 66% |

This halves the GB-seconds consumed per invocation. While still within free tier, the reduction provides more free-tier headroom and would matter if usage ever exceeded the free tier threshold (saved compute would be ~50% less per invocation at $0.0000166667/GB-second).

### 6. CloudWatch — $0.13/month (Low Priority)

Current cost is minimal. Log retention has been set to **30 days** on all Lambda log groups (applied June 7, 2026 via `put-retention-policy`). This prevents unbounded log growth and the associated storage costs.

Log groups with 30-day retention:
- `/aws/lambda/Maxi80Backend-2025-Maxi80Lambda-xLZTcX6Y3GUM`
- `/aws/lambda/Maxi80Backend-2025-IcecastMetadataCollector-GtapVCrulilc`
- `/aws/lambda/Maxi80Backend-2025-IcecastMetadataCollector-N9c051h1k27A` (old)

**Estimated savings:** CloudWatch Logs ingestion is $0.57/GB. The collector Lambda logs ~0.5 KB per invocation × 14,400 invocations/month ≈ 7 MB/month ingestion (negligible). The real savings come from **not accumulating storage indefinitely** — CloudWatch Logs storage is $0.03/GB/month. Without retention, after 12 months of operation at ~7 MB/month you'd accumulate ~84 MB (still negligible at $0.003/month). But the retention policy is good hygiene that prevents surprises if logging volume increases.

### 7. AWS AppSync — $0.23/month

This appears to be a separate service not related to the Maxi80 backend (possibly from another project in the same account). If unused, deleting the AppSync API would save $0.23/month.

### 8. AWS CloudTrail — $0.18/month

CloudTrail management events are free for the first trail. The $0.18 suggests either data events are enabled or there's a second trail. Review with:
```bash
aws cloudtrail describe-trails --profile maxi80 --region eu-west-1
```

---

## Summary: What Would Be Most Effective

| Action | Monthly Savings | Effort | Status |
|--------|----------------|--------|--------|
| Investigate & eliminate 409 GB S3-IA | **Up to $5.11** | Medium (investigation needed) | ⏳ TODO |
| Migrate REST API → HTTP API + Lambda Authorizer | 71% cheaper per request ($1/M vs $3.50/M) | Medium | ✅ Done |
| Migrate Secrets Manager → SSM Parameter Store | $0.47 | Low | ✅ Done |
| Reduce Lambda memory 256→128 MB | Free tier headroom (50% less GB-s) | Trivial | ✅ Done |
| Set CloudWatch log retention to 30 days | Prevents future growth | Trivial | ✅ Done |
| Delete unused AppSync API | $0.23 | Trivial | ⏳ TODO |
| Review CloudTrail trails | $0.18 | Low | ⏳ TODO |
| Increase collector interval to 5 min | $0.11 | Trivial (1 line change) | ⏳ TODO |
| Delete v1/ prefix | $0.009 | Low | ⏳ TODO |
| **Total possible savings** | **~$6.11/month (85% of bill)** | | |

## Conclusion

Your Lambda, API Gateway, and compute costs are essentially **zero** thanks to free tier and ARM64/Graviton. The bill is dominated by a **mysterious 409 GB S3 Standard-IA storage charge** that doesn't match any visible objects. Investigating and resolving that single issue would eliminate ~73% of your total AWS spend for this account.

The application architecture itself is already very cost-efficient — serverless, ARM64, minimal memory, API key throttling. The main opportunity is storage housekeeping, not architectural changes.

---

## Proposed Improvement: Swap REST API for HTTP API + Lambda Authorizer

### Current Architecture (REST API + API Key)

```
Client → REST API Gateway (API Key auth) → Maxi80Lambda
```

- REST API pricing: **$3.50 per million requests** (eu-central-1)
- API Key validation is handled natively by API Gateway (no extra Lambda call)
- Usage plan enforces throttling (10 req/s burst 50) and quota (10K/day)

### Proposed Architecture (HTTP API + Lambda Authorizer)

```
Client → HTTP API Gateway → Lambda Authorizer (validates API key) → Maxi80Lambda
```

- HTTP API pricing: **$1.00 per million requests** (eu-central-1)
- Each request triggers **two Lambda invocations**: one for the authorizer, one for the business logic
- HTTP API supports Lambda authorizers with caching (configurable TTL)

### Cost Comparison

Current observed traffic: **~6 requests over 37 days** (~5 requests/month). This is extremely low, so both options cost effectively $0 with free tier. Let's model for realistic growth scenarios:

| Monthly Requests | REST API Cost | HTTP API Cost | Extra Lambda (authorizer) | HTTP API Total | Savings |
|-----------------|--------------|--------------|--------------------------|----------------|---------|
| 5,000 | $0.018 | $0.005 | $0.00 (free tier) | $0.005 | $0.013 |
| 100,000 | $0.35 | $0.10 | $0.00 (free tier) | $0.10 | $0.25 |
| 1,000,000 | $3.50 | $1.00 | $0.00 (free tier) | $1.00 | $2.50 |
| 10,000,000 | $35.00 | $10.00 | ~$2.10* | $12.10 | $22.90 |

*Lambda authorizer cost at 10M requests: 10M invocations × 128 MB × ~50ms avg = 6,250 GB-seconds ≈ $2.10 (beyond free tier of 400K GB-s). With authorizer caching enabled (e.g., 300s TTL), actual invocations drop dramatically.

### Key Considerations

**Pros of HTTP API + Lambda Authorizer:**
- **71% cheaper per request** ($1.00 vs $3.50 per million)
- **Lower latency** (~60% less API Gateway overhead per AWS docs)
- More flexible auth logic (can validate tokens, check IP, etc.)
- Authorizer results can be **cached** (5 min default, up to 1 hour) — reducing actual authorizer invocations to near zero for repeat clients

**Cons:**
- Two Lambda cold starts on first request (authorizer + business logic)
- No native usage plans/quotas (would need custom throttling logic in the authorizer or use WAF)
- Slightly more complex deployment (extra Lambda to build/deploy)
- If you want quota enforcement (10K/day limit), you'd need to implement it yourself or accept just rate limiting

**For your current traffic (~5 req/month):** The savings are negligible ($0.013/month). The migration makes sense only if:
1. You expect significant traffic growth (iOS app launch)
2. You value the lower latency
3. You're okay losing the built-in usage plan quotas

### Authorizer Caching Impact

With a 5-minute cache TTL (default for HTTP API authorizers), a single client making multiple requests would only trigger the authorizer once per 5 minutes. At your current usage, the authorizer would fire ~1 time per session, not per request. This makes the extra Lambda cost essentially zero.

### Recommendation

~~At current traffic levels, this migration saves **~$0.01/month** — not worth the complexity.~~ **Migration completed on June 7, 2026.** The REST API with API Key has been replaced by an HTTP API with a Lambda authorizer that reads the API key from SSM Parameter Store (`/maxi80/api-key`).

**New API endpoint:** `https://m0fjchl4pk.execute-api.eu-central-1.amazonaws.com/`

**Auth change for clients:** Replace `x-api-key` header with `Authorization` header containing the same key value.

**What was removed:**
- REST API Gateway (and its $3.50/M pricing)
- API Key resource
- Usage Plan + Usage Plan Key

**What was added:**
- HTTP API Gateway ($1.00/M pricing — 71% cheaper)
- AuthorizerLambda (128 MB, reads API key from SSM at cold start)
- CloudWatch alarm for high request count on the HTTP API

**Actual cost impact at current traffic (~5 req/month):** ~$0, but correctly positioned for growth.

### Implementation Reference

The `swift-aws-lambda-runtime` repo includes a working example at:
`Examples/APIGatewayV2+LambdaAuthorizer/`

Key pattern: use `APIGatewayLambdaAuthorizerSimpleResponse` (returns `isAuthorized: true/false`) with `EnableSimpleResponses: true` and `AuthorizerPayloadFormatVersion: "2.0"` in the SAM template.

The authorizer Lambda would read the expected API key from SSM Parameter Store (same pattern as the Apple Music secret) and compare against the `Authorization` header.

---

## Update: Secrets Manager → SSM Parameter Store Migration (June 7, 2026)

### What Changed

Migrated the Apple Music API credentials (`/maxi80/apple-music-key`) from **AWS Secrets Manager** to **SSM Parameter Store** (SecureString type, encrypted with the default `aws/ssm` KMS key).

### Cost Impact

| | Secrets Manager (before) | SSM Parameter Store (after) |
|--|--|--|
| **Storage** | $0.40/secret/month | **Free** (Standard tier) |
| **API calls** | $0.05 per 10K calls | **Free** (Standard throughput, <40 TPS) |
| **KMS** | Included | Free (using default `aws/ssm` key) |

### Estimated Savings

The IcecastMetadataCollector Lambda runs every 3 minutes = ~14,400 invocations/month. Each cold start calls `GetParameter` once (warm invocations reuse the cached token factory, so no additional calls).

- **Secrets Manager cost was:** $0.40 (storage) + ~$0.07 (API calls for ~14,400 GetSecretValue) = **~$0.47/month**
- **SSM Parameter Store cost is:** $0.00 (free storage) + $0.00 (Standard throughput under 40 TPS) = **$0.00/month**

**Net savings: ~$0.47/month ($5.64/year)**

This is a modest absolute saving, but it's a **100% reduction** in secrets-related costs and removes the most expensive per-unit-priced service for this use case. More importantly, it simplifies the IAM permissions and removes a dependency on a service that offers no meaningful benefit over SSM Parameter Store for a static secret that doesn't need rotation.
