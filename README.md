# Maxi80 Backend

A Swift-based serverless backend for the Maxi80 radio station iOS app, providing Apple Music integration and station information through AWS Lambda and API Gateway.

## Overview

Maxi80 Backend is a modern Swift serverless application that provides:

- **Station Information**: Returns Maxi80 radio station details and streaming information
- **Apple Music Search**: Integrates with Apple Music API to search for artists, albums, and songs
- **Secure Authentication**: Uses JWT tokens for Apple Music API authentication
- **AWS Integration**: Leverages AWS Secrets Manager for secure credential storage
- **CLI Tools**: Command-line interface for testing and secret management

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   iOS App       │───▶│   API Gateway    │───▶│  Lambda Function│
│                 │    │  (REST API)      │    │   (Swift)       │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                        │
                                                        ▼
                       ┌─────────────────┐    ┌─────────────────┐
                       │ Apple Music API │◀───│ AWS Secrets     │
                       │                 │    │ Manager         │
                       └─────────────────┘    └─────────────────┘
```

## Project Structure

```
Sources/
├── Maxi80Lambda/           # AWS Lambda handler
│   ├── Lambda.swift        # Main Lambda function
│   └── LambdaError.swift   # Error definitions
├── Maxi80Backend/          # Core backend library
│   ├── AppleMusic/         # Apple Music API integration
│   │   ├── AppleMusic.swift
│   │   ├── AppleMusicAuthentication.swift
│   │   └── AppleMusicModel.swift
│   ├── AWS/                # AWS service integrations
│   │   ├── Region.swift
│   │   ├── S3Cache.swift
│   │   └── SecretsManager.swift
│   ├── APIClient/          # HTTP client utilities
│   │   ├── HTTPClient.swift
│   │   └── HTTPLogger.swift
│   ├── Endpoint.swift      # API endpoint definitions
│   └── Station.swift       # Station data model
└── Maxi80CLI/              # Command-line interface
    ├── CLIMain.swift       # CLI entry point
    ├── CLISearch.swift     # Search command
    ├── CLIManageSecret.swift # Secret management
    ├── GlobalOptions.swift # Shared CLI options
    └── Secret.swift        # Secret definitions
```

## API Endpoints

### GET /station
Returns Maxi80 radio station information.

**Response:**
```json
{
  "name": "Maxi 80",
  "streamUrl": "https://audio1.maxi80.com",
  "image": "maxi80_nocover-b.png",
  "shortDesc": "La radio de toute une génération",
  "longDesc": "Le meilleur de la musique des années 80",
  "websiteUrl": "https://maxi80.com",
  "donationUrl": "https://www.maxi80.com/paypal.htm"
}
```

### GET /search?term={query}
Searches Apple Music for artists, albums, and songs.

**Parameters:**
- `term` (required): Search query string

**Response:**
Returns Apple Music API search results in JSON format.

## Prerequisites

- **Swift 6.2+**
- **Docker** (for Lambda packaging)
- **AWS CLI** configured with appropriate credentials
- **SAM CLI** for deployment
- **Apple Music API credentials** (Team ID, Key ID, Private Key)

## Setup

### 1. Clone and Install Dependencies

```bash
git clone <repository-url>
cd maxi-80-backend-swift
swift package resolve
```

### 2. Configure AWS Credentials

Set up your AWS profile for the target account:

```bash
aws configure --profile maxi80
# Enter your AWS Access Key ID, Secret Access Key, and region (eu-central-1)
```

### 3. Store Apple Music Credentials

Create a `Sources/Maxi80CLI/Secret.swift` file (not tracked in git):

```swift
import Maxi80Backend

enum Secret {
    static let name = "Maxi80-AppleMusicKey"
    static let appleMusicSecret = AppleMusicSecret(
        privateKey: "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
        teamId: "YOUR_TEAM_ID",
        keyId: "YOUR_KEY_ID"
    )
}
```

Store the secret in AWS Secrets Manager:

```bash
swift run Maxi80CLI --profile maxi80 --region eu-central-1 store-secrets
```

## Building and Deployment

### Build the Lambda Function

```bash
make build
```

This command:
- Compiles the Swift code using Docker
- Packages the Lambda function
- Prepares the SAM build artifacts

### Deploy to AWS

```bash
make deploy
```

This deploys the entire stack including:
- Lambda function
- API Gateway
- IAM roles and policies
- CloudWatch alarms
- SNS topic for monitoring

### Format Code

```bash
make format
```

## Testing the API

### Test Station Endpoint

```bash
make call-station
```

### Test Search Endpoint

```bash
make call-search
```

### Get API Key

```bash
make get-api-key
```

## CLI Usage

The project includes a command-line interface for testing and management:

### Search Apple Music

```bash
swift run Maxi80CLI --profile maxi80 --region eu-central-1 search "Pink Floyd"
```

### Manage Secrets

```bash
# Store secrets
swift run Maxi80CLI --profile maxi80 --region eu-central-1 store-secrets

# Retrieve secrets
swift run Maxi80CLI --profile maxi80 --region eu-central-1 get-secrets
```

## Configuration

### Environment Variables

The Lambda function uses these environment variables:

- `SECRETS`: Name of the secret in AWS Secrets Manager (default: "Maxi80-AppleMusicKey")
- `LOG_LEVEL`: Logging level (trace, debug, info, notice, warning, error, critical)
- `AWS_REGION`: AWS region for services

### SAM Configuration

The deployment configuration is in `samconfig.toml`:

```toml
[dev.deploy.parameters]
stack_name = "Maxi80Backend-2025"
region = "eu-central-1"
profile = "maxi80"
capabilities = "CAPABILITY_IAM"
```

## Security Features

- **API Key Authentication**: All endpoints require a valid API key
- **JWT Token Management**: Automatic Apple Music JWT token generation and caching
- **Secrets Management**: Apple Music credentials stored securely in AWS Secrets Manager
- **IAM Least Privilege**: Lambda function has minimal required permissions
- **Rate Limiting**: API Gateway throttling and quotas configured

## Monitoring and Alerts

The stack includes CloudWatch alarms for:

- **4XX Errors**: API Gateway client errors (including throttling)
- **High Request Count**: Approaching daily quota limits
- **Lambda Errors**: Function execution failures
- **Lambda Duration**: High execution times

Alerts are sent to an SNS topic for notification setup.

## Development

### Adding New Endpoints

1. Add the endpoint to `Maxi80Endpoint` enum
2. Implement the handler in `Lambda.swift`
3. Update the routing logic in the `handle` method

### Testing Locally

Use the CLI for local testing:

```bash
swift run Maxi80CLI search "test query"
```

### Code Style

The project uses `swift-format` for consistent code formatting:

```bash
make format
```

## Dependencies

- **AWS Lambda Runtime**: Swift runtime for AWS Lambda
- **AWS Lambda Events**: Event types for API Gateway integration
- **JWT Kit**: JWT token generation for Apple Music API
- **AWS SDK Swift**: AWS service integrations (Secrets Manager, S3)
- **Async HTTP Client**: HTTP client for Apple Music API calls
- **Swift Log**: Structured logging
- **Swift Argument Parser**: CLI argument parsing

## License

[Add your license information here]

## Contributing

[Add contribution guidelines here]