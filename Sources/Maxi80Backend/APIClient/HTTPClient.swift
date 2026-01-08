//
//  HTTPClient.swift
//  Maxi80
//
//  Created by Stormacq, Sebastien on 14/04/2024.
//

import AsyncHTTPClient
import Foundation
import NIOCore
import NIOFoundationCompat
import NIOHTTP1

// provide common code for all network clients
public struct Maxi80HTTPClient: Sendable {

    public init() {}

    private let standardHeaders: [String: String] = [
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest",
        "User-Agent": "maxi80/1.0",
    ]

    // generic API CALL method
    // this is used by authentication API calls
    public func apiCall(
        url: URL,
        method: NIOHTTP1.HTTPMethod = .GET,
        body: Data? = nil,
        headers: [String: String] = [:]
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

        await logRequest(request)

        // send request with that session
        let response = try await HTTPClient.shared.execute(request, timeout: .seconds(10))
        guard response.status == .ok else {
            log.error("\(response.status.reasonPhrase)")
            log.debug("URLResponse : \(response.status)")
            throw URLError(.badServerResponse)
        }

        let responseSize = Int(response.headers.first(name: "content-length") ?? "") ?? 0
        var bytes = try? await response.body.collect(upTo: max(responseSize, 1024 * 1024 * 10))  //10 Mb maximum

        guard let readableBytes = bytes?.readableBytes,
            let data = bytes?.readData(length: readableBytes)
        else {
            log.debug("No readable bytes in the response")
            throw URLError(.zeroByteResource)
        }

        logResponse(response, data: data, error: nil)

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
