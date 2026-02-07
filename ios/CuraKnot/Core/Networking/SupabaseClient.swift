import Foundation
import os

private let logger = Logger(subsystem: "com.curaknot.app", category: "SupabaseClient")

// MARK: - Supabase Client

actor SupabaseClient {
    // MARK: - Properties
    
    let url: URL
    let anonKey: String
    private var accessToken: String?
    private var refreshToken: String?
    
    private let session: URLSession
    
    // MARK: - Initialization
    
    init(url: URL, anonKey: String) {
        self.url = url
        self.anonKey = anonKey
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - Auth
    
    func setSession(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
    
    func clearSession() {
        self.accessToken = nil
        self.refreshToken = nil
    }
    
    var isAuthenticated: Bool {
        accessToken != nil
    }
    
    // MARK: - REST Endpoints

    func from(_ table: String) -> PostgrestQueryBuilder {
        PostgrestQueryBuilder(client: self, table: table)
    }

    // MARK: - RPC (Database Functions)

    func rpc<T: Decodable>(_ functionName: String, params: [String: Any] = [:]) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: params)
        let (data, _) = try await request(
            path: "rest/v1/rpc/\(functionName)",
            method: "POST",
            body: body
        )
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }

    func rpc(_ functionName: String, params: [String: Any] = [:]) async throws {
        let body = try JSONSerialization.data(withJSONObject: params)
        _ = try await request(
            path: "rest/v1/rpc/\(functionName)",
            method: "POST",
            body: body
        )
    }
    
    // MARK: - Edge Functions
    
    func functions(_ functionName: String) -> EdgeFunctionBuilder {
        EdgeFunctionBuilder(client: self, functionName: functionName)
    }
    
    // MARK: - Storage
    
    func storage(_ bucket: String) -> StorageClient {
        StorageClient(client: self, bucket: bucket)
    }
    
    // MARK: - Internal Request Helpers
    
    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        // Build URL by appending path to base URL string
        var baseString = url.absoluteString
        if !baseString.hasSuffix("/") {
            baseString += "/"
        }
        
        // Handle paths that start with /
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        guard let requestURL = URL(string: baseString + cleanPath) else {
            throw SupabaseError.invalidURL
        }
        
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = method
        urlRequest.httpBody = body
        
        // Default headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        
        if let accessToken = accessToken {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        // Custom headers
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        let (data, response) = try await session.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.invalidResponse
        }
        
        // Debug logging (SECURITY: Never log response bodies - may contain PHI)
        #if DEBUG
        logger.debug("[\(method, privacy: .public)] \(requestURL.path, privacy: .public) -> \(httpResponse.statusCode)")
        #endif
        
        if httpResponse.statusCode >= 400 {
            throw SupabaseError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
        
        return (data, httpResponse)
    }
}

// MARK: - Postgrest Query Builder

struct PostgrestQueryBuilder {
    let client: SupabaseClient
    let table: String
    var filters: [String] = []
    var selectColumns: String = "*"
    var orderColumn: String?
    var orderAscending: Bool = true
    var limitCount: Int?
    var offsetCount: Int?
    
    func select(_ columns: String = "*") -> PostgrestQueryBuilder {
        var builder = self
        builder.selectColumns = columns
        return builder
    }
    
    func eq(_ column: String, _ value: String) -> PostgrestQueryBuilder {
        var builder = self
        builder.filters.append("\(column)=eq.\(value)")
        return builder
    }

    func eq(_ column: String, value: String) -> PostgrestQueryBuilder {
        eq(column, value)
    }

    func `in`(_ column: String, values: [String]) -> PostgrestQueryBuilder {
        var builder = self
        let quoted = values.map { "\"\($0)\"" }.joined(separator: ",")
        builder.filters.append("\(column)=in.(\(quoted))")
        return builder
    }

    func gte(_ column: String, value: String) -> PostgrestQueryBuilder {
        var builder = self
        builder.filters.append("\(column)=gte.\(value)")
        return builder
    }
    
    func gt(_ column: String, _ value: String) -> PostgrestQueryBuilder {
        var builder = self
        builder.filters.append("\(column)=gt.\(value)")
        return builder
    }

    func `is`(_ column: String, value: Any?) -> PostgrestQueryBuilder {
        var builder = self
        if value == nil {
            builder.filters.append("\(column)=is.null")
        } else {
            builder.filters.append("\(column)=is.\(value!)")
        }
        return builder
    }

    func neq(_ column: String, _ value: String) -> PostgrestQueryBuilder {
        var builder = self
        builder.filters.append("\(column)=neq.\(value)")
        return builder
    }

    func or(_ filterExpression: String) -> PostgrestQueryBuilder {
        var builder = self
        builder.filters.append("or=(\(filterExpression))")
        return builder
    }
    
    func order(_ column: String, ascending: Bool = true) -> PostgrestQueryBuilder {
        var builder = self
        builder.orderColumn = column
        builder.orderAscending = ascending
        return builder
    }
    
    func limit(_ count: Int) -> PostgrestQueryBuilder {
        var builder = self
        builder.limitCount = count
        return builder
    }
    
    func execute<T: Decodable>() async throws -> [T] {
        var path = "rest/v1/\(table)?select=\(selectColumns)"

        for filter in filters {
            path += "&\(filter)"
        }

        if let orderColumn = orderColumn {
            path += "&order=\(orderColumn).\(orderAscending ? "asc" : "desc")"
        }

        if let limitCount = limitCount {
            path += "&limit=\(limitCount)"
        }

        let (data, _) = try await client.request(path: path)
        return try JSONDecoder.supabase.decode([T].self, from: data)
    }

    
    func insert<T: Encodable>(_ item: T) -> PostgrestInsertBuilder {
        PostgrestInsertBuilder(client: client, table: table, item: item)
    }

    func insert(_ dictionary: [String: Any?]) -> PostgrestInsertBuilder {
        let cleanDict = dictionary.compactMapValues { $0 }
        return PostgrestInsertBuilder(client: client, table: table, dictionary: cleanDict)
    }

    func upsert<T: Encodable>(_ item: T) -> PostgrestUpsertBuilder {
        PostgrestUpsertBuilder(client: client, table: table, item: item)
    }

    func upsert(_ dictionary: [String: Any?]) -> PostgrestUpsertBuilder {
        let cleanDict = dictionary.compactMapValues { $0 }
        return PostgrestUpsertBuilder(client: client, table: table, dictionary: cleanDict)
    }

    func update<T: Encodable>(_ item: T) -> PostgrestUpdateBuilder {
        PostgrestUpdateBuilder(client: client, table: table, filters: filters, item: item)
    }

    func update(_ dictionary: [String: Any?]) -> PostgrestUpdateBuilder {
        let cleanDict = dictionary.compactMapValues { $0 }
        return PostgrestUpdateBuilder(client: client, table: table, filters: filters, dictionary: cleanDict)
    }
    
    func delete() async throws {
        var path = "rest/v1/\(table)"
        if !filters.isEmpty {
            path += "?" + filters.joined(separator: "&")
        }

        _ = try await client.request(path: path, method: "DELETE")
    }
}

// MARK: - Postgrest Insert Builder

struct PostgrestInsertBuilder {
    let client: SupabaseClient
    let table: String
    private var body: Data?
    private var dictionary: [String: Any]?

    init<T: Encodable>(client: SupabaseClient, table: String, item: T) {
        self.client = client
        self.table = table
        self.body = try? JSONEncoder.supabase.encode(item)
    }

    init(client: SupabaseClient, table: String, dictionary: [String: Any]) {
        self.client = client
        self.table = table
        self.dictionary = dictionary
    }

    func execute() async throws {
        let bodyData: Data
        if let body = body {
            bodyData = body
        } else if let dict = dictionary {
            bodyData = try JSONSerialization.data(withJSONObject: dict)
        } else {
            throw SupabaseError.invalidResponse
        }

        _ = try await client.request(
            path: "rest/v1/\(table)",
            method: "POST",
            body: bodyData,
            headers: ["Prefer": "return=minimal"]
        )
    }
}

// MARK: - Postgrest Upsert Builder

struct PostgrestUpsertBuilder {
    let client: SupabaseClient
    let table: String
    private var body: Data?
    private var dictionary: [String: Any]?

    init<T: Encodable>(client: SupabaseClient, table: String, item: T) {
        self.client = client
        self.table = table
        self.body = try? JSONEncoder.supabase.encode(item)
    }

    init(client: SupabaseClient, table: String, dictionary: [String: Any]) {
        self.client = client
        self.table = table
        self.dictionary = dictionary
    }

    func execute() async throws {
        let bodyData: Data
        if let body = body {
            bodyData = body
        } else if let dict = dictionary {
            bodyData = try JSONSerialization.data(withJSONObject: dict)
        } else {
            throw SupabaseError.invalidResponse
        }

        _ = try await client.request(
            path: "rest/v1/\(table)",
            method: "POST",
            body: bodyData,
            headers: ["Prefer": "return=minimal,resolution=merge-duplicates"]
        )
    }
}

// MARK: - Postgrest Update Builder

struct PostgrestUpdateBuilder {
    let client: SupabaseClient
    let table: String
    var filters: [String]
    private var body: Data?
    private var dictionary: [String: Any]?

    init<T: Encodable>(client: SupabaseClient, table: String, filters: [String], item: T) {
        self.client = client
        self.table = table
        self.filters = filters
        self.body = try? JSONEncoder.supabase.encode(item)
    }

    init(client: SupabaseClient, table: String, filters: [String], dictionary: [String: Any]) {
        self.client = client
        self.table = table
        self.filters = filters
        self.dictionary = dictionary
    }

    func eq(_ column: String, _ value: String) -> PostgrestUpdateBuilder {
        var builder = self
        builder.filters.append("\(column)=eq.\(value)")
        return builder
    }

    func neq(_ column: String, _ value: String) -> PostgrestUpdateBuilder {
        var builder = self
        builder.filters.append("\(column)=neq.\(value)")
        return builder
    }

    func or(_ filterExpression: String) -> PostgrestUpdateBuilder {
        var builder = self
        builder.filters.append("or=(\(filterExpression))")
        return builder
    }

    func execute() async throws {
        var path = "rest/v1/\(table)"
        if !filters.isEmpty {
            path += "?" + filters.joined(separator: "&")
        }

        let bodyData: Data
        if let body = body {
            bodyData = body
        } else if let dict = dictionary {
            bodyData = try JSONSerialization.data(withJSONObject: dict)
        } else {
            throw SupabaseError.invalidResponse
        }

        _ = try await client.request(
            path: path,
            method: "PATCH",
            body: bodyData,
            headers: ["Prefer": "return=minimal"]
        )
    }

    func executeReturning<T: Decodable>() async throws -> [T] {
        var path = "rest/v1/\(table)?select=*"
        if !filters.isEmpty {
            path += "&" + filters.joined(separator: "&")
        }

        let bodyData: Data
        if let body = body {
            bodyData = body
        } else if let dict = dictionary {
            bodyData = try JSONSerialization.data(withJSONObject: dict)
        } else {
            throw SupabaseError.invalidResponse
        }

        let (data, _) = try await client.request(
            path: path,
            method: "PATCH",
            body: bodyData,
            headers: ["Prefer": "return=representation"]
        )

        return try JSONDecoder.supabase.decode([T].self, from: data)
    }
}

// MARK: - Edge Function Builder

struct EdgeFunctionBuilder {
    let client: SupabaseClient
    let functionName: String
    
    func invoke<T: Decodable>(body: Encodable? = nil) async throws -> T {
        var bodyData: Data?
        if let body = body {
            bodyData = try JSONEncoder.supabase.encode(body)
        }
        
        let (data, _) = try await client.request(
            path: "functions/v1/\(functionName)",
            method: "POST",
            body: bodyData
        )
        
        return try JSONDecoder.supabase.decode(T.self, from: data)
    }
    
    func invoke(body: Encodable? = nil) async throws {
        var bodyData: Data?
        if let body = body {
            bodyData = try JSONEncoder.supabase.encode(body)
        }
        
        _ = try await client.request(
            path: "functions/v1/\(functionName)",
            method: "POST",
            body: bodyData
        )
    }
}

// MARK: - Storage Client

struct StorageClient {
    let client: SupabaseClient
    let bucket: String
    
    func upload(path: String, data: Data, contentType: String) async throws -> String {
        let (_, _) = try await client.request(
            path: "storage/v1/object/\(bucket)/\(path)",
            method: "POST",
            body: data,
            headers: ["Content-Type": contentType]
        )
        return path
    }
    
    func createSignedURL(path: String, expiresIn: Int = 3600) async throws -> URL {
        struct SignedURLRequest: Encodable {
            let expiresIn: Int
        }
        
        struct SignedURLResponse: Decodable {
            let signedURL: String
        }
        
        let body = try JSONEncoder.supabase.encode(SignedURLRequest(expiresIn: expiresIn))
        let (data, _) = try await client.request(
            path: "storage/v1/object/sign/\(bucket)/\(path)",
            method: "POST",
            body: body
        )
        
        let response = try JSONDecoder.supabase.decode(SignedURLResponse.self, from: data)
        guard let url = URL(string: response.signedURL) else {
            throw SupabaseError.invalidResponse
        }
        return url
    }
    
    func download(path: String) async throws -> Data {
        let (data, _) = try await client.request(
            path: "storage/v1/object/\(bucket)/\(path)"
        )
        return data
    }
    
    func remove(path: String) async throws {
        _ = try await client.request(
            path: "storage/v1/object/\(bucket)/\(path)",
            method: "DELETE"
        )
    }
}

// MARK: - Supabase Error

enum SupabaseError: Error, LocalizedError {
    case invalidResponse
    case invalidURL
    case httpError(statusCode: Int, data: Data)
    case authError(String)
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidURL:
            return "Invalid URL"
        case .httpError(let statusCode, let data):
            if let message = String(data: data, encoding: .utf8) {
                return "HTTP \(statusCode): \(message)"
            }
            return "HTTP error: \(statusCode)"
        case .authError(let message):
            return "Authentication error: \(message)"
        case .notAuthenticated:
            return "Not authenticated"
        }
    }
}

// MARK: - JSON Coders

extension JSONEncoder {
    static let supabase: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
