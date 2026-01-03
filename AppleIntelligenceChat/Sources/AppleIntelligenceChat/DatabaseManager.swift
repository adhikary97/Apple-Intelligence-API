import Foundation
import SQLite

final class DatabaseManager {
    static let shared = DatabaseManager()

    private var db: Connection?

    // Table definitions
    private let threads = Table("threads")
    private let messages = Table("messages")

    // Thread columns
    private let threadId = Expression<String>("id")
    private let threadTitle = Expression<String>("title")
    private let threadCreatedAt = Expression<Date>("created_at")
    private let threadUpdatedAt = Expression<Date>("updated_at")

    // Message columns
    private let messageId = Expression<String>("id")
    private let messageThreadId = Expression<String>("thread_id")
    private let messageRole = Expression<String>("role")
    private let messageContent = Expression<String>("content")
    private let messageTimestamp = Expression<Date>("timestamp")

    private init() {
        setupDatabase()
    }

    private var databasePath: String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("AppleIntelligenceChat", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: appDirectory.path) {
            try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }

        return appDirectory.appendingPathComponent("chat.db").path
    }

    private func setupDatabase() {
        do {
            db = try Connection(databasePath)
            try createTables()
            print("Database initialized at: \(databasePath)")
        } catch {
            print("Database setup error: \(error). Starting fresh.")
            // If there's an error, try to delete and recreate
            try? FileManager.default.removeItem(atPath: databasePath)
            do {
                db = try Connection(databasePath)
                try createTables()
            } catch {
                print("Failed to recreate database: \(error)")
            }
        }
    }

    private func createTables() throws {
        guard let db = db else { return }

        // Create threads table
        try db.run(threads.create(ifNotExists: true) { t in
            t.column(threadId, primaryKey: true)
            t.column(threadTitle)
            t.column(threadCreatedAt)
            t.column(threadUpdatedAt)
        })

        // Create messages table
        try db.run(messages.create(ifNotExists: true) { t in
            t.column(messageId, primaryKey: true)
            t.column(messageThreadId)
            t.column(messageRole)
            t.column(messageContent)
            t.column(messageTimestamp)
        })

        // Create index on thread_id for faster message lookups
        try db.run(messages.createIndex(messageThreadId, ifNotExists: true))
    }

    /// Ensures database exists and is valid, recreates if needed
    func ensureDatabase() {
        guard let db = db else {
            setupDatabase()
            return
        }

        // Check if database file still exists
        if !FileManager.default.fileExists(atPath: databasePath) {
            print("Database file was deleted, recreating...")
            setupDatabase()
            return
        }

        // Try a simple query to verify database is valid
        do {
            _ = try db.scalar(threads.count)
        } catch {
            print("Database appears corrupted, recreating: \(error)")
            try? FileManager.default.removeItem(atPath: databasePath)
            setupDatabase()
        }
    }

    // MARK: - Thread Operations

    func saveThread(_ thread: ChatThread) {
        ensureDatabase()
        guard let db = db else { return }

        do {
            let insert = threads.insert(or: .replace,
                threadId <- thread.id.uuidString,
                threadTitle <- thread.title,
                threadCreatedAt <- thread.createdAt,
                threadUpdatedAt <- thread.updatedAt
            )
            try db.run(insert)
        } catch {
            print("Error saving thread: \(error)")
        }
    }

    func deleteThread(_ thread: ChatThread) {
        ensureDatabase()
        guard let db = db else { return }

        do {
            // Delete all messages for this thread
            let threadMessages = messages.filter(messageThreadId == thread.id.uuidString)
            try db.run(threadMessages.delete())

            // Delete the thread
            let threadRow = threads.filter(threadId == thread.id.uuidString)
            try db.run(threadRow.delete())
        } catch {
            print("Error deleting thread: \(error)")
        }
    }

    func loadAllThreads() -> [ChatThread] {
        ensureDatabase()
        guard let db = db else { return [] }

        var loadedThreads: [ChatThread] = []

        do {
            for row in try db.prepare(threads.order(threadUpdatedAt.desc)) {
                guard let uuid = UUID(uuidString: row[threadId]) else { continue }

                var thread = ChatThread(
                    id: uuid,
                    title: row[threadTitle],
                    messages: [],
                    createdAt: row[threadCreatedAt],
                    updatedAt: row[threadUpdatedAt]
                )

                // Load messages for this thread
                thread.messages = loadMessages(forThreadId: uuid)
                loadedThreads.append(thread)
            }
        } catch {
            print("Error loading threads: \(error)")
        }

        return loadedThreads
    }

    // MARK: - Message Operations

    func saveMessage(_ message: ChatMessage, threadId: UUID) {
        ensureDatabase()
        guard let db = db else { return }

        // Don't save streaming messages
        guard !message.isStreaming else { return }

        do {
            let insert = messages.insert(or: .replace,
                messageId <- message.id.uuidString,
                messageThreadId <- threadId.uuidString,
                messageRole <- message.role.rawValue,
                messageContent <- message.content,
                messageTimestamp <- message.timestamp
            )
            try db.run(insert)
        } catch {
            print("Error saving message: \(error)")
        }
    }

    func updateMessage(_ message: ChatMessage, threadId: UUID) {
        ensureDatabase()
        guard let db = db else { return }

        // Don't save streaming messages
        guard !message.isStreaming else { return }

        do {
            let messageRow = messages.filter(messageId == message.id.uuidString)
            try db.run(messageRow.update(
                messageContent <- message.content
            ))
        } catch {
            print("Error updating message: \(error)")
        }
    }

    func deleteMessages(forThreadId threadUUID: UUID) {
        ensureDatabase()
        guard let db = db else { return }

        do {
            let threadMessages = messages.filter(messageThreadId == threadUUID.uuidString)
            try db.run(threadMessages.delete())
        } catch {
            print("Error deleting messages: \(error)")
        }
    }

    private func loadMessages(forThreadId threadUUID: UUID) -> [ChatMessage] {
        guard let db = db else { return [] }

        var loadedMessages: [ChatMessage] = []

        do {
            let query = messages
                .filter(messageThreadId == threadUUID.uuidString)
                .order(messageTimestamp.asc)

            for row in try db.prepare(query) {
                guard let uuid = UUID(uuidString: row[messageId]),
                      let role = MessageRole(rawValue: row[messageRole]) else { continue }

                let message = ChatMessage(
                    id: uuid,
                    role: role,
                    content: row[messageContent],
                    timestamp: row[messageTimestamp]
                )
                loadedMessages.append(message)
            }
        } catch {
            print("Error loading messages: \(error)")
        }

        return loadedMessages
    }
}
