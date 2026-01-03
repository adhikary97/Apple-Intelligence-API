import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case decodingError(Error)
    case streamingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .streamingError(let message):
            return "Streaming error: \(message)"
        }
    }
}

actor APIClient {
    private let baseURL: String
    private let session: URLSession
    
    init(baseURL: String) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }
    
    func sendMessage(
        messages: [ChatMessage],
        settings: AppSettings
    ) async throws -> AsyncThrowingStream<String, Error> {
        guard let url = URL(string: "\(baseURL)/api/v1/chat/completions") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build API messages including system prompt
        var apiMessages: [APIMessage] = []
        
        if !settings.systemPrompt.isEmpty {
            apiMessages.append(APIMessage(role: "system", content: settings.systemPrompt))
        }
        
        for message in messages {
            apiMessages.append(APIMessage(role: message.role.rawValue, content: message.content))
        }
        
        let requestBody = ChatCompletionRequest(
            messages: apiMessages,
            model: settings.selectedModel,
            stream: true,
            max_tokens: settings.maxTokens,
            temperature: settings.temperature
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, "Request failed")
        }
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))
                            
                            if jsonString == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            
                            if let data = jsonString.data(using: .utf8) {
                                do {
                                    let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                                    if let content = response.choices.first?.delta?.content {
                                        continuation.yield(content)
                                    }
                                } catch {
                                    // Skip malformed chunks
                                    continue
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    func sendMessageNonStreaming(
        messages: [ChatMessage],
        settings: AppSettings
    ) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/v1/chat/completions") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var apiMessages: [APIMessage] = []
        
        if !settings.systemPrompt.isEmpty {
            apiMessages.append(APIMessage(role: "system", content: settings.systemPrompt))
        }
        
        for message in messages {
            apiMessages.append(APIMessage(role: message.role.rawValue, content: message.content))
        }
        
        let requestBody = ChatCompletionRequest(
            messages: apiMessages,
            model: settings.selectedModel,
            stream: false,
            max_tokens: settings.maxTokens,
            temperature: settings.temperature
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
        
        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return completionResponse.choices.first?.message?.content ?? ""
    }
}

