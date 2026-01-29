import Foundation
import CryptoKit

/// Signs URLRequests with AWS Signature Version 4 for API Gateway IAM authentication
struct SigV4Signer {
    let accessKey: String
    let secretKey: String
    let sessionToken: String?
    let region: String
    let service = "execute-api"
    
    func sign(request: URLRequest) -> URLRequest {
        var signedRequest = request
        let date = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let amzDate = dateFormatter.string(from: date).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "Z", with: "")
        let dateStamp = String(amzDate.prefix(8))
        
        // Add required headers
        signedRequest.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        signedRequest.setValue(request.url?.host ?? "", forHTTPHeaderField: "Host")
        if let token = sessionToken {
            signedRequest.setValue(token, forHTTPHeaderField: "X-Amz-Security-Token")
        }
        
        // Create canonical request
        let method = request.httpMethod ?? "GET"
        let canonicalUri = request.url?.path ?? "/"
        let canonicalQueryString = request.url?.query ?? ""
        let canonicalHeaders = "host:\(request.url?.host ?? "")\nx-amz-date:\(amzDate)\n" + (sessionToken != nil ? "x-amz-security-token:\(sessionToken!)\n" : "")
        let signedHeaders = sessionToken != nil ? "host;x-amz-date;x-amz-security-token" : "host;x-amz-date"
        let payloadHash = sha256("")
        
        let canonicalRequest = "\(method)\n\(canonicalUri)\n\(canonicalQueryString)\n\(canonicalHeaders)\n\(signedHeaders)\n\(payloadHash)"
        
        // Create string to sign
        let credentialScope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n\(sha256(canonicalRequest))"
        
        // Calculate signature
        let signingKey = getSignatureKey(key: secretKey, dateStamp: dateStamp, regionName: region, serviceName: service)
        let signature = hmacSHA256(data: stringToSign, key: signingKey).map { String(format: "%02x", $0) }.joined()
        
        // Add authorization header
        let authorizationHeader = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        signedRequest.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        
        return signedRequest
    }
    
    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    
    private func hmacSHA256(data: String, key: Data) -> Data {
        let dataBytes = Data(data.utf8)
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: dataBytes, using: symmetricKey)
        return Data(signature)
    }
    
    private func getSignatureKey(key: String, dateStamp: String, regionName: String, serviceName: String) -> Data {
        let kDate = hmacSHA256(data: dateStamp, key: Data("AWS4\(key)".utf8))
        let kRegion = hmacSHA256(data: regionName, key: kDate)
        let kService = hmacSHA256(data: serviceName, key: kRegion)
        let kSigning = hmacSHA256(data: "aws4_request", key: kService)
        return kSigning
    }
}
