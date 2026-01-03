import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var sidebarWidth: CGFloat = 260
    @State private var showSidebar: Bool = true
    
    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.06, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            HStack(spacing: 0) {
                // Sidebar
                if showSidebar {
                    SidebarView(viewModel: viewModel)
                        .frame(width: sidebarWidth)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                }
                
                // Main chat area
                VStack(spacing: 0) {
                    // Header
                    HeaderView(viewModel: viewModel, showSidebar: $showSidebar)
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                    
                    // Chat area
                    if viewModel.messages.isEmpty {
                        EmptyStateView()
                    } else {
                        ChatMessagesView(viewModel: viewModel)
                    }
                    
                    // Error banner
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) {
                            viewModel.errorMessage = nil
                        }
                    }
                    
                    // Input area
                    ChatInputView(viewModel: viewModel)
                }
            }
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
    }
}

// MARK: - Sidebar View
struct SidebarView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var hoveredThreadId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Sidebar header
            HStack {
                Text("Chats")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                Button(action: { viewModel.createNewThread() }) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("New chat")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            Divider()
                .background(Color.white.opacity(0.1))
            
            // Thread list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.threads) { thread in
                        ThreadRow(
                            thread: thread,
                            isSelected: thread.id == viewModel.currentThreadId,
                            isHovered: hoveredThreadId == thread.id,
                            onSelect: { viewModel.selectThread(thread) },
                            onDelete: { viewModel.deleteThread(thread) }
                        )
                        .onHover { isHovered in
                            hoveredThreadId = isHovered ? thread.id : nil
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            
            Spacer()
            
            // New chat button at bottom
            Button(action: { viewModel.createNewThread() }) {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                    
                    Text("New Chat")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.08))
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .background(Color.black.opacity(0.3))
    }
}

struct ThreadRow: View {
    let thread: ChatThread
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            // Chat icon
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white : .white.opacity(0.5))
            
            // Thread info
            VStack(alignment: .leading, spacing: 3) {
                Text(thread.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                    .lineLimit(1)
                
                Text(thread.messages.isEmpty ? "No messages" : "\(thread.messages.count) messages")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            // Delete button (show on hover)
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(4)
                        .background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: [
                                Color(red: 0.4, green: 0.3, blue: 0.8).opacity(0.5),
                                Color(red: 0.5, green: 0.35, blue: 0.85).opacity(0.3)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        : LinearGradient(
                            colors: [
                                isHovered ? Color.white.opacity(0.08) : Color.clear,
                                isHovered ? Color.white.opacity(0.05) : Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Header View
struct HeaderView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var showSidebar: Bool
    
    var body: some View {
        HStack {
            // Toggle sidebar button
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showSidebar.toggle() } }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help(showSidebar ? "Hide sidebar" : "Show sidebar")
            
            // App icon and title
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0),
                                    Color(red: 0.4, green: 0.2, blue: 0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentThread?.title ?? "Apple Intelligence")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Text(viewModel.settings.selectedModel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(.leading, 8)
            
            Spacer()
            
            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isLoading ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                
                Text(viewModel.isLoading ? "Generating..." : "Ready")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: { viewModel.clearCurrentChat() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Clear chat")
                .disabled(viewModel.messages.isEmpty)
                
                Button(action: { viewModel.showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.2))
    }
}

// MARK: - Empty State
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.3),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.7, green: 0.5, blue: 1.0),
                                Color(red: 0.5, green: 0.3, blue: 0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            VStack(spacing: 12) {
                Text("Start a conversation")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Ask anything. Apple Intelligence is here to help.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
            
            // Quick prompts
            VStack(spacing: 12) {
                QuickPromptButton(text: "Explain quantum computing simply", icon: "atom")
                QuickPromptButton(text: "Write a haiku about coding", icon: "pencil")
                QuickPromptButton(text: "What makes a good API design?", icon: "curlybraces")
            }
            .padding(.top, 20)
            
            Spacer()
            Spacer()
        }
        .padding()
    }
}

struct QuickPromptButton: View {
    let text: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.6))
            
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Chat Messages
struct ChatMessagesView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var isUser: Bool {
        message.role == .user
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isUser {
                Spacer(minLength: 60)
            }
            
            if !isUser {
                // AI Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.6, green: 0.4, blue: 1.0),
                                    Color(red: 0.4, green: 0.2, blue: 0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                Text(message.content.isEmpty && message.isStreaming ? "..." : message.content)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(isUser ? .white : .white.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(
                                isUser
                                    ? LinearGradient(
                                        colors: [
                                            Color(red: 0.4, green: 0.3, blue: 0.9),
                                            Color(red: 0.5, green: 0.3, blue: 0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.1),
                                            Color.white.opacity(0.08)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                            )
                    )
                
                if message.isStreaming {
                    HStack(spacing: 4) {
                        TypingIndicator()
                    }
                    .padding(.leading, 8)
                }
            }
            
            if isUser {
                // User Avatar
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var animationPhase = 0.0
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .offset(y: sin(animationPhase + Double(index) * 0.5) * 3)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
        }
    }
}

// MARK: - Error Banner
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.9))
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.2))
    }
}

// MARK: - macOS Text Field
struct FocusableTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.placeholderString = placeholder
        textField.font = NSFont.systemFont(ofSize: 14)
        textField.textColor = NSColor.white
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.focusRingType = .none
        textField.drawsBackground = false
        textField.lineBreakMode = .byWordWrapping
        textField.cell?.wraps = true
        textField.cell?.isScrollable = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.refusesFirstResponder = false

        // Focus after the view is added to window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let window = textField.window {
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(textField)
            }
        }

        return textField
    }
    
    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusableTextField

        init(_ parent: FocusableTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            // Style the field editor when editing begins
            if let editor = textField.currentEditor() as? NSTextView {
                editor.insertionPointColor = .white
                editor.textColor = .white
                editor.backgroundColor = .clear
                editor.drawsBackground = false
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Style the text view on every command to ensure white text
            textView.insertionPointColor = .white
            textView.textColor = .white

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return false
                }
                if !parent.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parent.onSubmit()
                }
                return true
            }
            return false
        }
    }
}

// MARK: - Chat Input
struct ChatInputView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.1))
            
            HStack(alignment: .bottom, spacing: 12) {
                // Text field
                FocusableTextField(
                    text: $viewModel.inputText,
                    placeholder: "Message Apple Intelligence...",
                    onSubmit: {
                        if !viewModel.inputText.isEmpty && !viewModel.isLoading {
                            viewModel.sendMessage()
                        }
                    }
                )
                .frame(minHeight: 44)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(Color.white.opacity(0.08))
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                
                // Send/Stop button
                Button(action: {
                    if viewModel.isLoading {
                        viewModel.stopGeneration()
                    } else {
                        viewModel.sendMessage()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: viewModel.isLoading
                                        ? [Color.red.opacity(0.9), Color.red.opacity(0.7)]
                                        : [Color(red: 0.5, green: 0.4, blue: 0.95), Color(red: 0.4, green: 0.3, blue: 0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isLoading && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(!viewModel.isLoading && viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.3))
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Button("Done") {
                    viewModel.updateServerURL()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.5, green: 0.4, blue: 0.9))
            }
            .padding()
            .background(Color.black.opacity(0.3))
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Server settings
                    SettingsSection(title: "Server") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Server URL")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            
                            TextField("http://localhost:8080", text: $viewModel.settings.serverURL)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                    
                    // Model settings
                    SettingsSection(title: "Model") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            
                            Picker("Model", selection: $viewModel.settings.selectedModel) {
                                Text("Base").tag("base")
                                Text("Permissive").tag("permissive")
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    
                    // Generation settings
                    SettingsSection(title: "Generation") {
                        VStack(spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Temperature")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Spacer()
                                    
                                    Text(String(format: "%.1f", viewModel.settings.temperature))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Slider(value: $viewModel.settings.temperature, in: 0...2, step: 0.1)
                                    .tint(Color(red: 0.5, green: 0.4, blue: 0.9))
                            }
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Max Tokens")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    Spacer()
                                    
                                    Text("\(viewModel.settings.maxTokens)")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                                
                                Slider(value: Binding(
                                    get: { Double(viewModel.settings.maxTokens) },
                                    set: { viewModel.settings.maxTokens = Int($0) }
                                ), in: 256...4096, step: 256)
                                    .tint(Color(red: 0.5, green: 0.4, blue: 0.9))
                            }
                        }
                    }
                    
                    // System prompt
                    SettingsSection(title: "System Prompt") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Customize AI behavior")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.6))
                            
                            TextEditor(text: $viewModel.settings.systemPrompt)
                                .font(.system(size: 13))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .frame(height: 100)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 550)
        .background(
            Color(red: 0.08, green: 0.06, blue: 0.14)
        )
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    ContentView()
        .frame(width: 900, height: 700)
}
