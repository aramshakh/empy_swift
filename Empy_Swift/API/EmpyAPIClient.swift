//
//  EmpyAPIClient.swift
//  Empy_Swift
//
//  HTTP client for the Empy backend API (async/await)
//

import Foundation

// MARK: - Errors

enum EmpyAPIError: LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)
    case noConversation
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingError(let err):
            return "Decoding error: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .noConversation:
            return "No active conversation"
        }
    }
}

// MARK: - Client

final class EmpyAPIClient {
    private let baseURL: String
    private let session: URLSession
    private let logger: SessionLogger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    init(
        baseURL: String = AppConfig.empyAPIBaseURL,
        logger: SessionLogger = .shared
    ) {
        self.baseURL = baseURL
        self.logger = logger
        self.session = URLSession(configuration: .default)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    // MARK: - Public API
    
    func healthCheck() async throws -> HealthResponse {
        return try await get(path: "/health")
    }
    
    func createConversation(_ request: CreateConversationRequest) async throws -> CreateConversationResponse {
        return try await post(path: "/conversation", body: request)
    }
    
    func processTranscripts(_ request: ProcessRequest) async throws -> ProcessResponse {
        return try await post(path: "/process", body: request)
    }
    
    func endConversation(id: String) async throws -> EndConversationResponse {
        return try await postEmpty(path: "/conversation/\(id)/end")
    }
    
    func getAdvice(_ request: AdviceRequest) async throws -> AdviceResponse {
        return try await post(path: "/advice", body: request)
    }
    
    // MARK: - Private HTTP Helpers
    
    private func get<R: Decodable>(path: String) async throws -> R {
        guard let url = URL(string: baseURL + path) else {
            throw EmpyAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        return try await execute(request)
    }
    
    private func post<T: Encodable, R: Decodable>(path: String, body: T) async throws -> R {
        guard let url = URL(string: baseURL + path) else {
            throw EmpyAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try encoder.encode(body)
        
        return try await execute(request)
    }
    
    private func postEmpty<R: Decodable>(path: String) async throws -> R {
        guard let url = URL(string: baseURL + path) else {
            throw EmpyAPIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        
        return try await execute(request)
    }
    
    private func execute<R: Decodable>(_ request: URLRequest) async throws -> R {
        let startTime = Date()
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "unknown"
        
        logger.log(
            event: "api_request_start",
            layer: "api",
            details: ["method": method, "path": path]
        )
        
        do {
            let (data, response) = try await session.data(for: request)
            let elapsed = Date().timeIntervalSince(startTime)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw EmpyAPIError.networkError(
                    NSError(domain: "EmpyAPI", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Not HTTP response"])
                )
            }
            
            logger.log(
                event: "api_response",
                layer: "api",
                details: [
                    "method": method,
                    "path": path,
                    "status": "\(httpResponse.statusCode)",
                    "elapsed_ms": "\(Int(elapsed * 1000))",
                    "bytes": "\(data.count)"
                ]
            )
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                throw EmpyAPIError.httpError(statusCode: httpResponse.statusCode, body: body)
            }
            
            return try decoder.decode(R.self, from: data)
            
        } catch let error as EmpyAPIError {
            throw error
        } catch let error as DecodingError {
            logger.log(
                event: "api_decode_error",
                layer: "api",
                details: ["error": "\(error)", "path": path]
            )
            throw EmpyAPIError.decodingError(error)
        } catch {
            logger.log(
                event: "api_network_error",
                layer: "api",
                details: ["error": error.localizedDescription, "path": path]
            )
            throw EmpyAPIError.networkError(error)
        }
    }
}
