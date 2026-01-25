#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif 

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public class Maxi80APIClient {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSessionProtocol
    
    public init(baseURL: URL, apiKey: String, session: URLSessionProtocol = URLSession.shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }
    
    public func getStation() async throws -> Station {
        let url = baseURL.appendingPathComponent("/station")
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(Station.self, from: data)
    }
    
    public func search(term: String) async throws -> AppleMusicSearchResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/search"), resolvingAgainstBaseURL: true)
        components?.queryItems = [URLQueryItem(name: "term", value: term)]
        
        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return try JSONDecoder().decode(AppleMusicSearchResponse.self, from: data)
    }
}

public enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
