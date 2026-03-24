---
inclusion: fileMatch
fileMatchPattern: "template.yaml,**/Lambda.swift,**/S3Writer.swift,**/SecretsManager.swift"
---

# Lambda Runtime Constraint

All Lambda functions in this project MUST use `Runtime: provided.al2`. Do NOT change them to `provided.al2023`.

The binary built by `swift package archive` dynamically links against `libcrypto.so.10` (OpenSSL 1.0.x from the AL2 build container). AL2023 ships `libcrypto.so.3` (OpenSSL 3.x) and does not include `libcrypto.so.10`, so the dynamic linker fails immediately on startup:

```
/var/task/bootstrap: error while loading shared libraries: libcrypto.so.10: cannot open shared object file: No such file or directory
```

This constraint applies until the build toolchain (`swift package archive`) produces binaries linked against AL2023's OpenSSL, or the dependencies are fully statically linked.

# AWS SDK Client Initialization — No Concurrent Creation

Do NOT create multiple AWS SDK clients (S3Client, SecretsManagerClient, etc.) concurrently using `async let` or task groups. The CRT's internal TLS context singleton (`SDKDefaultIO`) has a race condition on first initialization that causes the same "Tls Context failed to create" fatal error.

```
ClientRuntime/SDKDefaultIO.swift:77: Fatal error: Tls Context failed to create.
```

Always create AWS SDK clients sequentially during Lambda init. Once the first client has been created (and the TLS context is initialized), subsequent clients are safe. See: https://github.com/awslabs/aws-sdk-swift/issues/1077
