# IcecastMetadataCollector Lambda

A Swift Lambda function that monitors the Maxi80 Icecast radio stream, extracts the currently playing track, searches Apple Music for metadata and artwork, and stores everything in S3. It also maintains a rolling `history.json` file of recently played tracks for the iOS client.

## How It Works

Every 2 minutes (via EventBridge schedule), the Lambda:

1. Reads the Icecast stream to extract the current artist/title
2. Checks S3 to see if this track was already collected
3. If new: searches Apple Music, downloads artwork, writes metadata/search/artwork to S3
4. Records the track in `<KEY_PREFIX>/history.json` (both cache-hit and cache-miss paths)

The history file is capped at `MAX_HISTORY_SIZE` entries (default 100) and is designed for direct consumption by the iOS app.

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `STREAM_URL` | Yes | — | Icecast stream URL (e.g. `https://audio1.maxi80.com`) |
| `S3_BUCKET` | Yes | — | S3 bucket for storing collected metadata |
| `KEY_PREFIX` | No | `collected` | S3 key prefix for all stored files |
| `SECRETS` | No | `Maxi80-AppleMusicKey` | Secrets Manager secret name |
| `LOG_LEVEL` | No | `info` | Log level (`trace`, `debug`, `info`, `warning`, `error`) |
| `MAX_HISTORY_SIZE` | No | `100` | Max entries in history.json |
| `AWS_REGION` | No | `eu-west-1` | AWS region (must match the S3 bucket region) |
| `AWS_PROFILE` | No | — | AWS credentials profile name (passed through to the AWS SDK) |

## 1. Test Locally

### Run unit tests

```bash
make test
```

This runs the full test suite including the HistoryManager property-based tests (serialization round-trip, size invariant, ordering, duplicate preservation) and edge case tests.

### Run only the collector tests

```bash
swift test --filter HistoryManagerTests
swift test --filter S3WriterTests
swift test --filter IcecastReaderTests
swift test --filter SongSelectorTests
```

### Invoke locally with `swift run`

You can run the Lambda locally without SAM. The Swift AWS Lambda Runtime starts a local HTTP server on port 7000 when it detects it's not running inside a real Lambda environment.

In one terminal, start the Lambda:

```bash
# Set the required environment variables
export STREAM_URL=https://audio1.maxi80.com
export S3_BUCKET=your-bucket-name
export KEY_PREFIX=collected
export AWS_PROFILE=maxi80
export AWS_REGION=eu-west-1
export LOG_LEVEL=debug

swift run IcecastMetadataCollector
```

In another terminal, send an EventBridge Scheduled event:

```bash
curl -v http://127.0.0.1:7000/invoke \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "version": "0",
    "id": "12345678-1234-1234-1234-123456789012",
    "detail-type": "Scheduled Event",
    "source": "aws.events",
    "account": "123456789012",
    "time": "2025-07-15T14:30:00Z",
    "region": "eu-central-1",
    "resources": [],
    "detail": {}
  }'
```

> Note: this still requires network access to the Icecast stream and Apple Music API, plus valid AWS credentials for Secrets Manager and S3.

### Invoke locally with SAM

You can also invoke the Lambda locally using SAM CLI. The function expects an EventBridge Scheduled event:

```bash
# Build first
sam build

# Invoke with a sample EventBridge event
sam local invoke IcecastMetadataCollector \
  --event - <<'EOF'
{
  "version": "0",
  "id": "12345678-1234-1234-1234-123456789012",
  "detail-type": "Scheduled Event",
  "source": "aws.events",
  "account": "123456789012",
  "time": "2025-07-15T14:30:00Z",
  "region": "eu-central-1",
  "resources": [],
  "detail": {}
}
EOF
```

> Note: local invocation requires network access to the Icecast stream and Apple Music API, plus valid AWS credentials for Secrets Manager and S3.

## 2. Deploy

### Build the Lambda

```bash
make build
```

This builds both Lambda functions (Maxi80Lambda and IcecastMetadataCollector) in a single Docker invocation, strips debug symbols from the binaries, and prepares the `.aws-sam/build/` directory for deployment.

### Deploy to AWS

```bash
make deploy
```

This deploys the full stack defined in `template.yaml`, including:
- The `IcecastMetadataCollector` Lambda (ARM64, 128 MB, 115s timeout)
- EventBridge rule triggering every 2 minutes
- IAM policy granting `s3:PutObject`, `s3:HeadObject`, `s3:GetObject` and Secrets Manager access
- Environment variables including `MAX_HISTORY_SIZE`

### Verify deployment

```bash
# Check the deployed stack
aws cloudformation describe-stacks \
  --stack-name Maxi80Backend-2025 \
  --region eu-central-1 \
  --profile maxi80 \
  --query "Stacks[0].StackStatus"
```

## 3. Test Remotely

### Invoke the Lambda manually

```bash
# Get the function name from CloudFormation
FUNCTION_NAME=$(aws cloudformation describe-stack-resource \
  --stack-name Maxi80Backend-2025 \
  --logical-resource-id IcecastMetadataCollector \
  --region eu-central-1 \
  --profile maxi80 \
  --query "StackResourceDetail.PhysicalResourceId" \
  --output text)

# Invoke it
aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --region eu-central-1 \
  --profile maxi80 \
  --payload '{"version":"0","id":"test","detail-type":"Scheduled Event","source":"aws.events","account":"000000000000","time":"2025-07-15T14:30:00Z","region":"eu-central-1","resources":[],"detail":{}}' \
  --cli-binary-format raw-in-base64-out \
  /dev/stdout
```

### Check the history file

```bash
# Find the bucket name
BUCKET=$(aws cloudformation describe-stack-resource \
  --stack-name Maxi80Backend-2025 \
  --logical-resource-id MetadataBucket \
  --region eu-central-1 \
  --profile maxi80 \
  --query "StackResourceDetail.PhysicalResourceId" \
  --output text)

# Download and pretty-print history.json
aws s3 cp "s3://$BUCKET/collected/history.json" - \
  --region eu-central-1 \
  --profile maxi80 | python3 -m json.tool
```

### Access logs

The Lambda uses JSON structured logging. Logs are in CloudWatch under the function's log group.

```bash
# Tail live logs (requires SAM CLI)
sam logs \
  --stack-name Maxi80Backend-2025 \
  --name IcecastMetadataCollector \
  --region eu-central-1 \
  --profile maxi80 \
  --tail

# Or fetch recent logs with the AWS CLI
aws logs tail \
  "/aws/lambda/$FUNCTION_NAME" \
  --region eu-central-1 \
  --profile maxi80 \
  --since 1h \
  --format short
```

### Filter logs for history-related events

```bash
aws logs filter-log-events \
  --log-group-name "/aws/lambda/$FUNCTION_NAME" \
  --region eu-central-1 \
  --profile maxi80 \
  --filter-pattern "history" \
  --start-time $(date -v-1H +%s000) \
  --query "events[].message" \
  --output text
```

## S3 Layout

```
<KEY_PREFIX>/
├── history.json                          ← Rolling history of recent tracks
├── <Artist>/
│   └── <Title>/
│       ├── metadata.json                 ← Raw Icecast metadata + timestamp
│       ├── search.json                   ← Apple Music search response
│       └── artwork.jpg                   ← Album artwork
└── ...
```

## history.json Format

```json
{
  "entries": [
    {
      "artist": "Duran Duran",
      "title": "Is there something i should know",
      "artwork": "collected/Duran Duran/Is there something i should know/artwork.jpg",
      "timestamp": "2025-07-15T14:30:00Z"
    }
  ]
}
```

Entries are ordered oldest-first (newest appended at the end). When the file exceeds `MAX_HISTORY_SIZE`, the oldest entries at the beginning are trimmed.
