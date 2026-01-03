import Foundation
import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var threads: [ChatThread] = []
    @Published var currentThreadId: UUID?
    @Published var inputText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var settings: AppSettings
    @Published var showSettings: Bool = false

    private var apiClient: APIClient
    private var currentTask: Task<Void, Never>?
    private let db = DatabaseManager.shared

    var currentThread: ChatThread? {
        get {
            threads.first { $0.id == currentThreadId }
        }
        set {
            if let newValue = newValue,
               let index = threads.firstIndex(where: { $0.id == currentThreadId }) {
                threads[index] = newValue
            }
        }
    }

    var messages: [ChatMessage] {
        currentThread?.messages ?? []
    }

    init() {
        let defaultSettings = AppSettings()
        self.settings = defaultSettings
        self.apiClient = APIClient(baseURL: defaultSettings.serverURL)

        // Load threads from database
        loadThreadsFromDB()

        // Create initial thread if none exist
        if threads.isEmpty {
            createNewThread()
        } else {
            currentThreadId = threads.first?.id
        }
    }

    private func loadThreadsFromDB() {
        threads = db.loadAllThreads()
    }

    func updateServerURL() {
        self.apiClient = APIClient(baseURL: settings.serverURL)
    }

    func createNewThread() {
        let newThread = ChatThread()
        threads.insert(newThread, at: 0)
        currentThreadId = newThread.id
        inputText = ""
        errorMessage = nil

        // Save to database
        db.saveThread(newThread)
    }

    func selectThread(_ thread: ChatThread) {
        currentThreadId = thread.id
        inputText = ""
        errorMessage = nil
    }

    func deleteThread(_ thread: ChatThread) {
        // Delete from database
        db.deleteThread(thread)

        threads.removeAll { $0.id == thread.id }

        // If we deleted the current thread, select another one or create new
        if currentThreadId == thread.id {
            if let firstThread = threads.first {
                currentThreadId = firstThread.id
            } else {
                createNewThread()
            }
        }
    }

    func sendMessage() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }
        guard !isLoading else { return }
        guard let threadIndex = threads.firstIndex(where: { $0.id == currentThreadId }) else { return }

        // Add user message
        let userMessage = ChatMessage(role: .user, content: trimmedInput)
        threads[threadIndex].messages.append(userMessage)
        threads[threadIndex].updatedAt = Date()

        // Update thread title based on first message
        if threads[threadIndex].messages.count == 1 {
            threads[threadIndex].title = String(trimmedInput.prefix(30))
        }

        // Save user message to database
        db.saveMessage(userMessage, threadId: threads[threadIndex].id)
        db.saveThread(threads[threadIndex])

        inputText = ""

        // Create placeholder for assistant response
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        threads[threadIndex].messages.append(assistantMessage)

        isLoading = true
        errorMessage = nil

        let messagesToSend = threads[threadIndex].messages.dropLast().map { $0 }
        let assistantMessageId = assistantMessage.id
        let threadId = threads[threadIndex].id

        currentTask = Task {
            do {
                let stream = try await apiClient.sendMessage(
                    messages: Array(messagesToSend),
                    settings: settings
                )

                for try await chunk in stream {
                    if let tIndex = threads.firstIndex(where: { $0.id == threadId }),
                       let mIndex = threads[tIndex].messages.lastIndex(where: { $0.id == assistantMessageId }) {
                        threads[tIndex].messages[mIndex].content += chunk
                    }
                }

                // Mark streaming as complete and save to database
                if let tIndex = threads.firstIndex(where: { $0.id == threadId }),
                   let mIndex = threads[tIndex].messages.lastIndex(where: { $0.id == assistantMessageId }) {
                    threads[tIndex].messages[mIndex].isStreaming = false
                    threads[tIndex].updatedAt = Date()

                    // Save completed assistant message to database
                    db.saveMessage(threads[tIndex].messages[mIndex], threadId: threadId)
                    db.saveThread(threads[tIndex])
                }

            } catch {
                // Remove the empty assistant message on error
                if let tIndex = threads.firstIndex(where: { $0.id == threadId }),
                   let mIndex = threads[tIndex].messages.lastIndex(where: { $0.id == assistantMessageId }) {
                    threads[tIndex].messages.remove(at: mIndex)
                }
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    func stopGeneration() {
        currentTask?.cancel()
        currentTask = nil
        isLoading = false

        // Mark any streaming message as complete and save
        if let threadIndex = threads.firstIndex(where: { $0.id == currentThreadId }) {
            let threadId = threads[threadIndex].id
            for i in threads[threadIndex].messages.indices {
                if threads[threadIndex].messages[i].isStreaming {
                    threads[threadIndex].messages[i].isStreaming = false

                    // Save the stopped message if it has content
                    if !threads[threadIndex].messages[i].content.isEmpty {
                        db.saveMessage(threads[threadIndex].messages[i], threadId: threadId)
                    }
                }
            }
            db.saveThread(threads[threadIndex])
        }
    }

    func clearCurrentChat() {
        guard let threadIndex = threads.firstIndex(where: { $0.id == currentThreadId }) else { return }

        // Delete messages from database
        db.deleteMessages(forThreadId: threads[threadIndex].id)

        threads[threadIndex].messages.removeAll()
        threads[threadIndex].title = "New Chat"
        threads[threadIndex].updatedAt = Date()

        // Update thread in database
        db.saveThread(threads[threadIndex])

        errorMessage = nil
    }

    func retryLastMessage() {
        guard let threadIndex = threads.firstIndex(where: { $0.id == currentThreadId }) else { return }
        guard let lastUserIndex = threads[threadIndex].messages.lastIndex(where: { $0.role == .user }) else { return }

        let lastUserMessage = threads[threadIndex].messages[lastUserIndex]
        threads[threadIndex].messages = Array(threads[threadIndex].messages.prefix(lastUserIndex))

        inputText = lastUserMessage.content
        sendMessage()
    }
}
