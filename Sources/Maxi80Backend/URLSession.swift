#if canImport(FoundationNetworking)

import Foundation
import FoundationNetworking

/// Defines the possible errors
public enum URLSessionAsyncErrors: Error {
    case invalidUrlResponse, missingResponseData
}

public extension URLSession {
 
    /// A reimplementation of `URLSession.shared.data(for: url)` required for Linux
    ///
    /// - Parameter url: The URLRequest for which to load data.
    /// - Returns: Data and response.
    ///
    /// - Usage:
    ///
    ///     let (data, response) = try await URLSession.shared.asyncData(for: request)
    func asyncData(for request: URLRequest) async throws -> (Data, URLResponse) {

        return try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let response = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLSessionAsyncErrors.invalidUrlResponse)
                    return
                }
                guard let data = data else {
                    continuation.resume(throwing: URLSessionAsyncErrors.missingResponseData)
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }
}

#endif 