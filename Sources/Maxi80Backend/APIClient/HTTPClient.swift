import AsyncHTTPClient
import Logging
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

// provide common code for all network clients
public struct MusicAPIClient {

    private let logger: Logger
    public init(logger: Logger? = nil) {
        self.logger = logger ?? Logger(label: "MusicAPIClient")
    }

    private let standardHeaders: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "User-Agent": "maxi80/1.0",
    ]

    // generic API CALL method
    public func apiCall(
        url: URL,
        method: NIOHTTP1.HTTPMethod = .GET,
        body: Data? = nil,
        headers: [String: String] = [:],
        timeout: Int64 = 10
    ) async throws -> (Data, HTTPClientResponse) {

        // let's add provided headers to our request (keeping new value in case of conflicts)
        var requestHeaders = standardHeaders

        // add the headers our caller wants in this request
        requestHeaders.merge(headers, uniquingKeysWith: { (_, new) in new })

        // and build the request
        let request = self.request(
            for: url,
            method: method,
            withBody: body,
            withHeaders: requestHeaders
        )

        await logger.request(request)

        // send request with that session
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(timeout))
        guard response.status == .ok else {
            logger.error("\(response.status.reasonPhrase)")
            logger.trace("URLResponse : \(response.status)")
            throw HTTPClientError.badServerResponse(status: response.status)
        }

        guard let responseSize = Int(response.headers.first(name: "content-length") ?? ""),
            var bytes = try? await response.body.collect(upTo: max(responseSize, 1024 * 1024 * 10)),  //10 Mb maximum
            let data = bytes.readData(length: bytes.readableBytes)
        else {
            logger.debug("No readable bytes in the response")
            throw HTTPClientError.zeroByteResource
        }

        logger.response(response, data: data, error: nil)

        return (data, response)
    }

    // prepare an HTTPClientRequest for a given url, method, body, and headers
    // https://softwareengineering.stackexchange.com/questions/100959/how-do-you-unit-test-private-methods
    // by OOP design it should be private.  Make it internal (default) for testing
    private func request(
        for url: URL,
        method: NIOHTTP1.HTTPMethod = .GET,
        withBody body: Data? = nil,
        withHeaders headers: [String: String]? = nil
    ) -> HTTPClientRequest {

        // create the request
        var request = HTTPClientRequest(url: url.absoluteString)

        // add HTTP verb
        request.method = method

        // add body
        if let body {
            request.body = HTTPClientRequest.Body.bytes(ByteBuffer(data: body))
        }

        // add headers
        if let headers {
            for (key, value) in headers {
                request.headers.add(name: key, value: value)
            }
        }

        return request
    }
}

enum HTTPClientError: Error {
    case badServerResponse(status: HTTPResponseStatus)
    case zeroByteResource
}
