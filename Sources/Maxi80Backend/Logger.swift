//
//  Logger.swift
//  Maxi80
//
//  Created by Stormacq, Sebastien on 14/04/2024.
//

import Foundation

// defines a global logger that we could reuse through the project
#if !os(iOS)
import Logging

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// on Linux use the open source Logging library
#if DEBUG
public let log: Logger = Log.verboseLogger()
#else
public let log: Logger = Log.defaultLogger()
#endif

public struct Log {

    // defines a default logger
    public static func defaultLogger(logLevel: Logger.Level = .warning, label: String = "") -> Logger {
        let log = Log(logLevel: logLevel, label: label)
        return log.logger
    }
    public static func verboseLogger(logLevel: Logger.Level = .debug, label: String = "") -> Logger {
        let log = Log(logLevel: logLevel, label: label)
        return log.logger
    }

    private let logger: Logger
    private init(logLevel: Logger.Level = .warning, label: String = "") {
        var logger = Logger(label: label == "" ? "CLIlib" : label)
        logger.logLevel = logLevel   
        self.logger = logger 
    }
    

    // mutating func setLogLevel(level: Logger.Level) {
    //     defaultLogger.logLevel = level
    // }
}

//on iOS
#else
import OSLog
public let log = Logger()
#endif

func logRequest(_ request: URLRequest) {

    log.debug("\n - - - - - - - - - - OUTGOING - - - - - - - - - - \n")
    defer { log.debug("\n - - - - - - - - - -  END - - - - - - - - - - \n") }
    let urlAsString = request.url?.absoluteString ?? ""
    let urlComponents = URLComponents(string: urlAsString)
    let method = request.httpMethod != nil ? "\(request.httpMethod ?? "")" : ""
    let path = "\(urlComponents?.path ?? "")"
    let query = "\(urlComponents?.query ?? "")"
    let host = "\(urlComponents?.host ?? "")"
    var output = """
   \(urlAsString) \n\n
   \(method) \(path)?\(query) HTTP/1.1 \n
   HOST: \(host)\n
   """

    for (key, value) in request.allHTTPHeaderFields ?? [:] {
        output += "\(key): \(value)\n"

    }

    if let body = request.httpBody {
        output += "\n \(String(data: body, encoding: .utf8) ?? "")"
   }
    log.debug("\(output)")
}

func logResponse(_ response: HTTPURLResponse?, data: Data?, error: Error?) {

    log.debug("\n - - - - - - - - - - INCOMMING - - - - - - - - - - \n")
    defer { log.debug("\n - - - - - - - - - -  END - - - - - - - - - - \n") }
    let urlString = response?.url?.absoluteString
    let components = NSURLComponents(string: urlString ?? "")
    let path = "\(components?.path ?? "")"
    let query = "\(components?.query ?? "")"
    var output = ""
    if let urlString {
        output += "\(urlString)"
        output += "\n\n"
    }
    if let statusCode =  response?.statusCode {
        output += "HTTP \(statusCode) \(path)?\(query)\n"
    }
    if let host = components?.host {
        output += "Host: \(host)\n"
    }
    for (key, value) in response?.allHeaderFields ?? [:] {
        output += "\(key): \(value)\n"
    }
    if let data {
        output += "\n\(String(data: data, encoding: .utf8) ?? "")\n"
    }
    if error != nil {
        output += "\nError: \(error!.localizedDescription)\n"
    }
    log.debug("\(output)")
}

