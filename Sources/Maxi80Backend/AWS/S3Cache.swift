// import Foundation
// import AWSS3

// func downloadImageToS3(imageUrl: URL) async throws -> URL {
//   // Configure S3 client (replace with your credentials and region)
//   let credentialsProvider = AWSStaticCredentialsProvider(accessKey: "YOUR_ACCESS_KEY_ID", secretKey: "YOUR_SECRET_ACCESS_KEY")
//   let configuration = AWSServiceConfiguration(region: AWSRegionType.default)
//   let s3 = AWSS3(configuration: configuration, credentialsProvider: credentialsProvider)

//   // Extract filename from URL
//   let fileName = imageUrl.lastPathComponent

//   // Check if file already exists in S3
//   let headObjectRequest = S3HeadObjectRequest()
//   headObjectRequest.bucket = "YOUR_S3_BUCKET_NAME" // Replace with your bucket name
//   headObjectRequest.key = fileName
//   let headObjectResponse = try await s3.headObject(headObjectRequest)

//   // Download and upload to S3 if not found
//   if !headObjectResponse.exists {
//     guard let imageData = try? Data(contentsOf: imageUrl) else {
//       throw S3Error.downloadFailed(reason: "Failed to download image from \(imageUrl)")
//     }

//     let putObjectRequest = S3PutObjectRequest()
//     putObjectRequest.bucket = "YOUR_S3_BUCKET_NAME"
//     putObjectRequest.key = fileName
//     putObjectRequest.body = imageData

//     try await s3.putObject(putObjectRequest)
//   }

//   // Return the S3 object URL
//   return URL(string: "s3://YOUR_S3_BUCKET_NAME/\(fileName)")! // Replace with your bucket name
// }

// // Define S3 error enum for clarity
// enum S3Error: Error {
//   case downloadFailed(reason: String)
// }
