import Foundation

// MARK: - Chat Thread Model
struct ChatThread: Identifiable, Equatable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(title: String = "New Chat") {
        self.id = UUID()
        self.title = title
        self.messages = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Initializer for loading from database
    init(id: UUID, title: String, messages: [ChatMessage], createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var preview: String {
        if let lastMessage = messages.last {
            return String(lastMessage.content.prefix(50))
        }
        return "No messages yet"
    }

    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Chat Message Model
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool

    init(role: MessageRole, content: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
    }

    /// Initializer for loading from database
    init(id: UUID, role: MessageRole, content: String, timestamp: Date, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.isStreaming == rhs.isStreaming
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

// MARK: - API Request/Response Models
struct APIMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let messages: [APIMessage]
    let model: String
    let stream: Bool
    let max_tokens: Int?
    let temperature: Double?
}

struct ChatCompletionResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: ResponseMessage?
        let delta: ResponseMessage?
        let finish_reason: String?
    }
    
    struct ResponseMessage: Codable {
        let content: String?
        let role: String?
    }
}

// MARK: - Settings
struct AppSettings {
    var serverURL: String = "http://localhost:8080"
    var selectedModel: String = "base"
    var temperature: Double = 0.7
    var maxTokens: Int = 2048
    var systemPrompt: String = "You are a helpful AI assistant powered by Apple Intelligence."
}
