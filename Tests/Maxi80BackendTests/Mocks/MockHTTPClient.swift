import AsyncHTTPClient
import Foundation
import Logging
import Maxi80Backend
import NIOCore
import NIOHTTP1

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Mock HTTP client for testing
public final class MockHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    public struct CallRecord {
        public let url: URL
        public let method: NIOHTTP1.HTTPMethod
        public let body: Data?
        public let headers: [String: String]
        public let timeout: Int64
    }

    private var callRecords: [CallRecord] = []
    private var responseData: [Data] = []
    private var responseStatuses: [HTTPResponseStatus] = []
    private var errors: [Error] = []
    private var currentIndex = 0

    public init() {}

    public func apiCall(
        url: URL,
        method: NIOHTTP1.HTTPMethod = .GET,
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: Int64 = 10
    ) async throws -> (Data, HTTPClientResponse) {

        // Record the call
        let record = CallRecord(
            url: url,
            method: method,
            body: body,
            headers: headers,
            timeout: timeout
        )
        callRecords.append(record)

        // Check if we should throw an error
        if currentIndex < errors.count {
            let error = errors[currentIndex]
            currentIndex += 1
            throw error
        }

        // Return pre-configured response
        guard currentIndex < responseData.count else {
            throw HTTPClientError.zeroByteResource
        }

        let data = responseData[currentIndex]
        let status = responseStatuses[currentIndex]
        currentIndex += 1

        // Create a real response using httpbin.org (only for successful responses)
        // This is a simple approach that works for testing
        let client = HTTPClient.shared
        let testRequest = HTTPClientRequest(url: "https://httpbin.org/status/200")
        let response = try await client.execute(testRequest, timeout: .seconds(1))

        return (data, response)
    }

    // Test helper methods
    public func setResponse(data: Data, status: HTTPResponseStatus = .ok) {
        responseData.append(data)
        responseStatuses.append(status)
    }

    public func setError(_ error: Error) {
        errors.append(error)
    }

    public func getCallRecords() -> [CallRecord] {
        callRecords
    }

    public func reset() {
        callRecords.removeAll()
        responseData.removeAll()
        responseStatuses.removeAll()
        errors.removeAll()
        currentIndex = 0
    }
}
