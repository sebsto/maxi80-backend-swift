// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "maxi-80-backend-swift",
    platforms: [
        .macOS(.v14),
        .iOS(.v17) 
    ],
    products: [
        .executable(name: "Maxi80Lambda", targets: ["Maxi80Lambda"]),
        .library(name: "Maxi80Backend", targets: ["Maxi80Backend"]),
        .executable(name: "StoreSecret", targets: ["CLI"]),
    ],
    dependencies: [
        //TODO: tag specific versions instead of main branches
        .package(url: "https://github.com/sebsto/swift-aws-lambda-runtime", branch: "sebsto/deployerplugin_dsl"),
        .package(url: "https://github.com/swift-server/swift-aws-lambda-events.git", branch: "main"),
        .package(url: "https://github.com/vapor/jwt-kit.git", .upToNextMajor(from: "5.0.0-beta.1")),
        .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.5.0")),
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "0.41.0")
    ],
    targets: [
        .executableTarget(
            name: "Maxi80Lambda",
            dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
                .product(name: "AWSLambdaEvents", package: "swift-aws-lambda-events"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "AWSS3", package: "aws-sdk-swift"),
                .product(name: "AWSSecretsManager", package: "aws-sdk-swift"),
                .target(name: "Maxi80Backend")
            ]
        ),
        .target(
            name: "Maxi80Backend",
            dependencies: [
                .product(name: "Logging", package: "swift-log", condition: .when(platforms: [.linux, .macOS]))
            ]), 
        .executableTarget(
            name: "CLI",
            dependencies: [
                .product(name: "AWSSecretsManager", package: "aws-sdk-swift"),
            ]
        ),
        .testTarget(
            name: "maxi-80-backend-swiftTests",
            dependencies: ["Maxi80Lambda"]),
    ]
)
