import SwiftUI

// MARK: - Prompt (chat)

#if !APPSTORE
/// The mic's right-click menu: Automatic (the user's languages) or one fixed language.
private struct DictationLanguageMenu: View {
    @Bindable var dictation: MacDictation

    var body: some View {
        let automatic = MacDictation.automaticLocales().map(\.identifier)
        Picker(String(localized: "Dictation language"), selection: $dictation.language) {
            Text(String(localized: "Automatic") + " (" + automatic.map(MacDictation.name(of:)).joined(separator: ", ") + ")")
                .tag(MacDictation.automatic)
            ForEach(quickChoices(automatic), id: \.self) { id in
                Text(MacDictation.name(of: id)).tag(id)
            }
        }
        .pickerStyle(.inline)
        Menu(String(localized: "Other languages")) {
            Picker(String(localized: "Dictation language"), selection: $dictation.language) {
                ForEach(MacDictation.allLanguages, id: \.self) { id in
                    Text(MacDictation.name(of: id)).tag(id)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// Automatic's languages, plus the fixed one when it is another.
    private func quickChoices(_ automatic: [String]) -> [String] {
        let chosen = dictation.language
        return chosen == MacDictation.automatic || automatic.contains(chosen) ? automatic : automatic + [chosen]
    }
}
#endif

struct PromptView: View {
    @ObservedObject var state: AppState
    @State private var text: String = ""
    @FocusState private var focused: Bool
    @State private var showModelPicker = false

    #if !APPSTORE
    @State private var dictation = MacDictation()
    #endif
    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 6) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx).padding(.top, 4)
                }

                if !state.chatHistory.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(state.chatHistory) { msg in
                                    ChatBubble(message: msg).id(msg.id)
                                }
                                if state.stateOverride != nil {
                                    HStack { TypingDotsView(); Spacer(minLength: 32) }
                                        .id("typing")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onChange(of: state.chatHistory) { _, _ in
                            if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                        .onChange(of: state.stateOverride) { _, v in
                            if v != nil {
                                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                            } else if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear {
                            if let last = state.chatHistory.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }

                HStack(spacing: 0) {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showModelPicker.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: state.chatProvider.accentHex))
                                .frame(width: 6, height: 6)
                            Text(state.activeChatModel)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color(hex: "#7B8089"))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "#5C6370"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                        ModelPickerView(state: state, isPresented: $showModelPicker)
                            .frame(width: 300)
                    }
                }
                .padding(.horizontal, 10)

                HStack(spacing: 8) {
                    TextField(state.chatHistory.isEmpty ? String(localized: "Ask me anything…") : String(localized: "Continue…"), text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit { sendMessage() }

                    #if !APPSTORE
                    // Dictate instead of typing (on-device speech recognition when available)
                    Button {
                        Task {
                            if dictation.isRecording { text = await dictation.finish() }
                            else { await dictation.start(from: text) }
                        }
                    } label: {
                        Image(systemName: dictation.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(dictation.isRecording ? Color(hex: "#F4505E") : Color(hex: "#8E939C"))
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(dictation.isRecording ? String(localized: "Stop dictation") : String(localized: "Dictate (right-click to choose the language)"))
                    .contextMenu { DictationLanguageMenu(dictation: dictation) }
                    .onChange(of: dictation.transcript) { _, _ in
                        if dictation.isRecording { text = dictation.text }
                    }
                    #endif

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                    }
                    .buttonStyle(SendButtonStyle())
                    .disabled(text.isEmpty)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .simultaneousGesture(TapGesture().onEnded { focused = true })
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .padding(.bottom, 10)
        .onAppear { focused = true }
        .onChange(of: state.view) { _, view in
            if view == .prompt {
                state.fetchModelsIfNeeded(for: state.chatProvider)
            }
        }
        .onChange(of: state.chatProvider) { _, provider in
            if state.view == .prompt {
                state.fetchModelsIfNeeded(for: provider)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in
            guard state.view == .prompt else { return }
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            guard state.view == .prompt else { return }
            text = ""
            state.chatHistory = []
            ClaudeService.shared.clearConversation()
            focused = true
        }
    }

    private func sendMessage() {
        #if !APPSTORE
        // Still dictating: take the final words (and the right language) before sending.
        if dictation.isRecording {
            Task {
                text = await dictation.finish()
                sendMessage()
            }
            return
        }
        #endif
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        text = ""
        focused = false
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        Task {
            await ClaudeService.shared.chat(query: query, context: state.promptContext, state: state)
            await MainActor.run { focused = true }
        }
    }
}


// MARK: - Model / provider picker

/// Wrapping horizontal flow layout — used by ModelPickerView and QuestionView.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let r = rows(maxW: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return r.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let r = rows(maxW: bounds.width, subviews: subviews)
        for (idx, pt) in r.placements.enumerated() {
            subviews[idx].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }
    private func rows(maxW: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [(x: CGFloat, y: CGFloat)]) {
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        var pts: [(x: CGFloat, y: CGFloat)] = []
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            pts.append((x: x, y: y))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: max(maxX, 0), height: y + lineH), pts)
    }
}

struct ModelPickerView: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider chips — wrap; hide local providers when not connected and not already active
            let visibleProviders = ChatProvider.allCases.filter { p in
                if p == .ollama   { return !AppState.shared.ollamaServerURL.isEmpty   || state.chatProvider == .ollama }
                if p == .lmstudio { return !AppState.shared.lmstudioServerURL.isEmpty || state.chatProvider == .lmstudio }
                return true
            }
            ChipFlowLayout(spacing: 6) {
                ForEach(visibleProviders, id: \.self) { provider in
                    Button {
                        guard provider != state.chatProvider else { return }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                            state.chatProvider = provider
                        }
                        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
                        SoundEngine.shared.play("pop")
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: provider.accentHex))
                                .frame(width: 7, height: 7)
                            Text(provider.displayName)
                                .font(.system(size: 12, weight: state.chatProvider == provider ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(state.chatProvider == provider
                                    ? Color(hex: provider.accentHex).opacity(0.18)
                                    : Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(
                            state.chatProvider == provider
                                ? Color(hex: provider.accentHex).opacity(0.5)
                                : Color.white.opacity(0.1),
                            lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.2)

            // Model list for current provider — fetched dynamically
            modelListView
                .frame(height: 260, alignment: .top)
        }
        .padding(14)
        .background(Color(hex: "#16171B"))
        .onAppear {
            // Force-refresh local providers every time the picker opens
            if state.chatProvider.isLocal {
                state.fetchedProviderModels[state.chatProvider] = nil
                state.providerModelFetchError[state.chatProvider] = nil
            }
            state.fetchModelsIfNeeded(for: state.chatProvider)
        }
        .onChange(of: state.chatProvider) { _, provider in
            if provider.isLocal {
                state.fetchedProviderModels[provider] = nil
                state.providerModelFetchError[provider] = nil
            }
            state.fetchModelsIfNeeded(for: provider)
        }
    }

    @ViewBuilder
    private var modelListView: some View {
        if state.loadingProviderModels.contains(state.chatProvider) {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Loading models…")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A8F98"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        } else if let error = state.providerModelFetchError[state.chatProvider] {
            Text(error)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8A8F98"))
                .padding(.vertical, 4)
        } else if let models = state.fetchedProviderModels[state.chatProvider] {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(models, id: \.id) { model in
                        Button {
                            switch state.chatProvider {
                            case .anthropic: state.claudeModel = model.id
                            case .google:    state.googleChatModel = model.id
                            case .openai:    state.openAIChatModel = model.id
                            case .ollama:    state.ollamaChatModel = model.id
                            case .lmstudio:  state.lmstudioChatModel = model.id
                            }
                            isPresented = false
                            SoundEngine.shared.play("blip")
                        } label: {
                            HStack {
                                Text(model.label)
                                    .font(.system(size: 12))
                                    .foregroundColor(state.activeChatModel == model.id
                                                     ? Color(hex: state.chatProvider.accentHex)
                                                     : Color(hex: "#C8CDD4"))
                                Spacer()
                                if state.activeChatModel == model.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Color(hex: state.chatProvider.accentHex))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(state.activeChatModel == model.id
                                        ? Color(hex: state.chatProvider.accentHex).opacity(0.1)
                                        : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        if !message.content.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
                    Spacer(minLength: 32)
                    Text(message.content)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    ChatMarkdownView(markdown: message.content)
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

struct TypingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#6B7079"))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
    }
}

// MARK: - Searching

struct SearchingView: View {
    @ObservedObject var state: AppState

    var label: String {
        switch state.promptContext {
        case .window(_, let title, _): return String(format: String(localized: "Claude is reading %@…"), title)
        case .file(let name, _):       return String(format: String(localized: "Claude is reading %@…"), name)
        case nil:                      return String(localized: "Claude is searching…")
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 8) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx)
                }
                ShimmeringText(label)
                    .font(.system(size: 13.5))
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .green)

            if let result = state.searchResult {
                VStack(alignment: .leading, spacing: 7) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .semibold))

                    VStack(spacing: 4) {
                        ForEach(result.items.prefix(3), id: \.label) { item in
                            HStack {
                                Text(item.label).font(.system(size: 12.5, weight: .semibold))
                                Spacer()
                                Text(item.detail).font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if let note = result.note {
                        Text(note).font(.system(size: 11)).foregroundColor(Color(hex: "#6E737C"))
                    }

                    HStack(spacing: 8) {
                        // The URL comes from the model, which may have read attacker-controlled
                        // files or pages: only plain web links may leave the app.
                        let openURL = safeWebURL(result.items.first?.url)
                        PrimaryButton("Open") {
                            if let openURL { NSWorkspace.shared.open(openURL) }
                        }
                        .disabled(openURL == nil)
                        .help(openURL?.absoluteString ?? "")
                        SecondaryButton("Copy") {
                            let text = result.items.map { "\($0.label): \($0.detail)" }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        SecondaryButton("Close") { state.view = state.tasks.isEmpty ? .empty : .overview }
                    }
                }
                .padding(.leading, 84)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Chat-provider switch (used by AI pill buttons and ↗ action)

/// Mirrors ModelPickerView provider-chip tap: animates, fires surprised emote + "pop" sound,
/// then opens the chat view. No-op if provider is already selected (just opens chat).
@MainActor
func switchChatProvider(_ provider: ChatProvider) {
    let state = AppState.shared
    if provider != state.chatProvider {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            state.chatProvider = provider
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
    }
    state.view = .prompt
}
