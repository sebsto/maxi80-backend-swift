//
//  HTTPClient.swift
//  Maxi80
//
//  Created by Stormacq, Sebastien on 14/04/2024.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// make URLSession testable by abstracting its protocol
// it allows to use the real URLSession or a mock interchangably
public protocol URLSessionProtocol {
    func data(for request: URLRequest, delegate: URLSessionTaskDelegate?) async throws -> (Data, URLResponse)
}

// callers can express expected HTTP Response code either as range, either as specific value
public enum ExpectedResponseCode: Sendable {
    case range(Range<Int>)
    case value(Int)

    public func isValid(response: Int) -> Bool {
        switch self {
        case .range(let range):
                return range.contains(response)
        case .value(let value):
                return value == response
        }
    }
}

// provide common code for all network clients
public struct HTTPClient: Sendable {

    public enum HTTPVerb: String, Sendable {
        case GET
        case POST
    }

    public init() {}

    private func prepareAuthenticationHeaders() async -> [String: String] {

        let requestHeaders: [String: String]  = [ "Content-Type": "application/json",
                                                  "Accept": "application/json",
                                                  "X-Requested-With": "XMLHttpRequest",
                                                  "User-Agent": "curl/7.79.1"]

        return requestHeaders
    }

    // generic API CALL method
    // this is used by authentication API calls
    public func apiCall(url: URL,
                 method: HTTPVerb = .GET,
                 body: Data? = nil,
                 headers: [String: String] = [:],
                 validResponse: ExpectedResponseCode = .value(200)
    ) async throws -> (Data, HTTPURLResponse) {

        let request: URLRequest

        // let's add provided headers to our request (keeping new value in case of conflicts)
        var requestHeaders = await prepareAuthenticationHeaders()

        // add the headers our caller wants in this request
        requestHeaders.merge(headers, uniquingKeysWith: { (_, new) in new })

        // and build the request
        request  = self.request(for: url,
                                method: method,
                                withBody: body,
                                withHeaders: requestHeaders)

        logRequest(request)

        // send request with that session
        let session = URLSession.shared
#if canImport(FoundationNetworking)
        let (data, response) = try await session.asyncData(for: request)
#else
        let (data, response) = try await session.data(for: request)
#endif
        guard let httpResponse = response as? HTTPURLResponse,
              validResponse.isValid(response: httpResponse.statusCode) else {
            let errorMsg:String = "=== HTTP ERROR. Status code \((response as! HTTPURLResponse).statusCode) not in range \(validResponse) ==="
            log.error("\(errorMsg)")
            log.debug("URLResponse : \(response)")
            throw URLError(.badServerResponse)
        }

        logResponse(httpResponse, data: data, error: nil)

        return(data, httpResponse)
    }

    // prepare an URLRequest for a given url, method, body, and headers
    // https://softwareengineering.stackexchange.com/questions/100959/how-do-you-unit-test-private-methods
    // by OOP design it should be private.  Make it internal (default) for testing
    private func request(for url: URL,
                 method: HTTPVerb = .GET,
                 withBody body: Data? = nil,
                 withHeaders headers: [String: String]? = nil) -> URLRequest {

        // create the request
        var request = URLRequest(url: url)

        // add HTTP verb
        request.httpMethod = method.rawValue

        // add body
        if let body {
            request.httpBody = body
        }

        // add headers
        if let headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }
}

