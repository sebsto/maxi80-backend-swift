# Cognito Authentication Examples

This directory contains code for authenticating API Gateway requests using AWS Signature Version 4 (SigV4) with Amazon Cognito Identity Pools.

## Files

- **SigV4Signer.swift**: Core signing implementation for API Gateway IAM authentication
- **Usage.swift**: Example usage patterns with Cognito

## Architecture

```
┌─────────────────┐
│   iOS App       │
└────────┬────────┘
         │
         ▼
┌─────────────────────────┐
│  Cognito Identity Pool  │
│  (Temporary Credentials)│
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│   SigV4Signer           │
│   (Sign Request)        │
└────────┬────────────────┘
         │
         ▼
┌─────────────────────────┐
│   API Gateway           │
│   (IAM Authorization)   │
└─────────────────────────┘
```

## Setup

### 1. Create Cognito Identity Pool

```bash
aws cognito-identity create-identity-pool \
  --identity-pool-name "MyAppIdentityPool" \
  --allow-unauthenticated-identities \
  --region us-east-1
```

### 2. Configure IAM Roles

**Unauthenticated Role Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "execute-api:Invoke",
      "Resource": "arn:aws:execute-api:us-east-1:*:your-api-id/*/GET/*"
    }
  ]
}
```

**Authenticated Role Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "execute-api:Invoke",
      "Resource": "arn:aws:execute-api:us-east-1:*:your-api-id/*/*"
    }
  ]
}
```

### 3. Enable IAM Authorization on API Gateway

```bash
aws apigatewayv2 update-route \
  --api-id your-api-id \
  --route-id your-route-id \
  --authorization-type AWS_IAM
```

## Usage

### Anonymous Access

```swift
let credentialsProvider = AWSCognitoCredentialsProvider(
    regionType: .USEast1,
    identityPoolId: "us-east-1:xxxx-xxxx-xxxx"
)

let credentials = await credentialsProvider.credentials()

let signer = SigV4Signer(
    accessKey: credentials.accessKey,
    secretKey: credentials.secretKey,
    sessionToken: credentials.sessionToken,
    region: "us-east-1"
)

var request = URLRequest(url: URL(string: "https://api.example.com/prod/endpoint")!)
let signedRequest = signer.sign(request: request)

let (data, _) = try await URLSession.shared.data(for: signedRequest)
```

### Authenticated Access

```swift
credentialsProvider.logins = [
    AWSIdentityProviderApple: idToken
]

let credentials = await credentialsProvider.credentials()
// Use credentials with SigV4Signer as above
```

## Key Concepts

- **SigV4**: AWS authentication protocol that signs requests with temporary credentials
- **Identity Pool**: Provides temporary AWS credentials for authenticated and unauthenticated users
- **IAM Authorization**: API Gateway validates the signature and checks IAM permissions
- **Temporary Credentials**: Include access key, secret key, and session token (expire after 1 hour)

## Security Best Practices

- Never hardcode permanent AWS credentials in client apps
- Use Cognito Identity Pools for temporary credentials
- Apply least privilege IAM policies
- Enable CloudWatch logging for API Gateway
- Monitor unauthorized access attempts
