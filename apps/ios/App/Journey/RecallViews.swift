import SwiftUI
import MiloCore

struct ClassifyView: View {
    let model: JournalModel
    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                MiloPageHeader(title: "这份感受，来自哪里？", subtitle: "此刻，还是过去？", back: model.back)
                VStack(spacing: 18) {
                    choice("说说此刻", subtitle: "可以只吐槽，聊完就走", past: false, identifier: "choose-now-chat") { model.startPresentConversation() }
                    choice("自己写下来", subtitle: "安静地记下现在的心情", past: false) { model.chooseKind("now") }
                    choice("它来自过去", subtitle: "聊聊想起的那段时光", past: true) { model.chooseKind("past") }
                }.padding(.top, 8)
            }.padding(.horizontal, 24).padding(.bottom, 28)
        }.parityScrollMetrics("journey-classify")
    }
    private func choice(_ title: String, subtitle: String, past: Bool, identifier: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title).font(MiloTheme.serif(21)).foregroundStyle(past ? MiloTheme.dim : .white)
                    Text(subtitle).font(.subheadline).foregroundStyle(MiloTheme.dim)
                }
                Spacer(minLength: 8)
                Image(systemName: past ? "sparkles" : "sun.horizon").font(.title3.weight(.ultraLight)).foregroundStyle(MiloTheme.dim.opacity(0.55))
            }.padding(24).frame(maxWidth: .infinity, minHeight: 114, alignment: .leading)
                .background(past ? MiloTheme.accent.opacity(0.09) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(past ? MiloTheme.accent.opacity(0.40) : .white.opacity(0.09), lineWidth: 0.8))
        }.buttonStyle(MiloPressStyle()).accessibilityIdentifier(identifier ?? (past ? "choose-past" : "choose-now"))
    }
}

struct NowNoteView: View {
    @Bindable var model: JournalModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var preferredEditorHeight: CGFloat = 120
    @State private var editing = false
    private let editorBottom = "note-editor-bottom"
    var body: some View {
        // The inset reduces this proposal before the editor height is calculated,
        // so the native editor fits above both the keyboard and the save bar.
        GeometryReader { viewport in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 24) {
                        MiloPageHeader(title: "记下此刻", subtitle: "想写多少都可以", back: model.back)
                        MoodPlanet(mood: model.draft.mood, size: 120)
                        noteEditor(height: editorHeight(in: viewport.size.height))
                            .id(editorBottom)
                        Text(model.draft.labels.joined(separator: " · ")).font(.caption).foregroundStyle(MiloTheme.hint)
                    }.padding(.horizontal, 28).padding(.bottom, 24)
                }.parityScrollMetrics("journey-now-note")
                    .scrollDismissesKeyboard(.never)
                    .onChange(of: editing) { _, focused in
                        if focused { revealEditor(using: reader) }
                    }
                    .onChange(of: viewport.size) { _, _ in
                        if editing { revealEditor(using: reader) }
                    }
                    .onChange(of: dynamicTypeSize) { _, _ in
                        if editing { revealEditor(using: reader) }
                    }
            }
        }.safeAreaInset(edge: .bottom) {
            // iOS 26's keyboard toolbar floats over the save action. Keep both
            // controls in the measured inset so the editor reserves their space.
            VStack(spacing: 10) {
                if editing {
                    HStack {
                        Spacer()
                        Button { editing = false } label: {
                            Text("完成编辑").font(.subheadline.weight(.medium))
                                .foregroundStyle(MiloTheme.dim)
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(.ultraThinMaterial, in: Capsule())
                        }.buttonStyle(MiloPressStyle())
                            .accessibilityIdentifier("note-editor-done")
                    }
                }
                MiloPrimaryButton(title: "收藏这一刻") { editing = false; model.save() }
                    .disabled(!model.isLoaded || model.isSaving).accessibilityIdentifier("save-now")
            }.padding(.horizontal, 24).padding(.vertical, 14).background(MiloTheme.background)
        }
    }
    private func noteEditor(height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            MiloNoteEditor(text: $model.draft.note, isFocused: $editing)
                .parityTextMetrics("note-editor")
            if model.draft.note.isEmpty {
                Text("此刻的感受…（选填）").font(.body).foregroundStyle(MiloTheme.hint)
                    .padding(.horizontal, 5).padding(.top, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }.frame(height: height).miloPanel(padding: 18)
    }
    private func editorHeight(in availableHeight: CGFloat) -> CGFloat {
        // Reserve the panel's 36 points of padding and a small visible margin.
        let capacity = max(1, availableHeight - 48)
        return editing ? capacity : min(preferredEditorHeight, capacity)
    }
    private func revealEditor(using reader: ScrollViewProxy) {
        // Wait for focus/keyboard layout, never move the outer page on each key.
        Task { @MainActor in
            await Task.yield()
            guard editing else { return }
            reader.scrollTo(editorBottom, anchor: .bottom)
        }
    }
}

struct PastTimeView: View {
    @Bindable var model: JournalModel
    @State private var picked = ""
    @State private var custom = ""
    private let presets = ["昨天", "上个星期", "几个月前", "去年这个时候", "去年夏天", "几年前", "大学时光", "刚工作那会儿", "少年时代", "小时候"]
    private var mark: String { custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? picked : custom.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                MiloPageHeader(title: "那是什么时候的事？", subtitle: "大概的时间就好", back: model.back)
                FlowLayout(spacing: 10) {
                    ForEach(presets, id: \.self) { preset in
                        Button { picked = preset; custom = "" } label: {
                            Text(preset).font(.subheadline).foregroundStyle(MiloTheme.dim)
                                .padding(.horizontal, 18).padding(.vertical, 12)
                                .background(MiloTheme.accent.opacity(mark == preset ? 0.22 : 0.04), in: Capsule())
                                .overlay(Capsule().stroke(mark == preset ? MiloTheme.accent.opacity(0.8) : .white.opacity(0.1), lineWidth: 0.8))
                        }.buttonStyle(.plain).accessibilityIdentifier("time-\(preset)")
                            .accessibilityAddTraits(mark == preset ? [.isSelected] : [])
                    }
                }
                TextField("比如，高三的雨季", text: $custom).font(.body).foregroundStyle(MiloTheme.ink)
                    .padding(18).background(.white.opacity(0.05), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.7)).accessibilityIdentifier("custom-time")
            }.padding(.horizontal, 28).padding(.bottom, 24)
        }.parityScrollMetrics("journey-past-time")
            .scrollDismissesKeyboard(.never)
            .safeAreaInset(edge: .bottom) {
                MiloPrimaryButton(title: "回到那时") { model.startConversation(time: mark) }
                    .disabled(mark.isEmpty).accessibilityIdentifier("start-chat")
                    .padding(.horizontal, 24).padding(.vertical, 14).background(MiloTheme.background.opacity(0.93))
            }.onAppear {
                if let time = model.draft.timeMark { if presets.contains(time) { picked = time } else { custom = time } }
            }.onChange(of: mark) { _, value in model.setPendingTime(value) }
    }
}

struct ChatView: View {
    @Bindable var model: JournalModel
    @State private var speech = SpeechInputModel()
    @State private var speechPrefix = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var showConnection = false
    @FocusState private var editing: Bool
    private var aiBinding: Binding<Bool> { Binding(get: { model.draft.aiEnabled }, set: { model.setAIEnabled($0) }) }
    private var statusText: String {
        if speech.isRecording { return "正在听" }
        if model.isThinking { return "正在回复" }
        if model.aiUnavailableReason != nil { return "仅本地记录" }
        return model.chatNotice.isEmpty ? "此刻，慢慢说" : model.chatNotice
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(model.draft.transcript.enumerated()), id: \.offset) { index, message in
                            messageRow(message, index: index)
                        }
                        if model.isThinking {
                            ProgressView().controlSize(.small).tint(MiloTheme.accent)
                                .padding(.leading, 4).accessibilityLabel("正在生成回复")
                                .accessibilityIdentifier("chat-thinking-progress")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
                }.parityScrollMetrics("journey-chat")
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: model.draft.transcript.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) { reader.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: editing) { _, focused in
                        if focused { reader.scrollTo("bottom", anchor: .bottom) }
                    }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { editing = false }.accessibilityIdentifier("chat-editor-done")
            }
        }
        .sheet(isPresented: $showConnection) { connectionDetails }
        .onDisappear { speech.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { speech.stop() }
        }
        .onChange(of: speech.transcript) { _, text in
            guard !text.isEmpty else { return }
            model.draft.inputText = speechPrefix + (speechPrefix.isEmpty ? "" : "\n") + text
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { speech.stop(); editing = false; model.back() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("返回").accessibilityIdentifier("back")
            Button { editing = false; showConnection = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MILO").font(.system(size: 19, weight: .medium, design: .rounded)).tracking(1.4)
                    HStack(spacing: 5) {
                        Circle().fill(model.aiUnavailableReason == nil ? MiloTheme.accent : MiloTheme.hint)
                            .frame(width: 4, height: 4)
                        Text(statusText).font(.caption).lineLimit(2)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
                    }.foregroundStyle(MiloTheme.hint)
                }.frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.accessibilityIdentifier("chat-capability-notice")
                .accessibilityHint(AIFeaturePolicy.isAvailable ? "查看模型状态和设置" : "查看本地记录说明")
            Spacer(minLength: 8)
            if model.canRetryReply {
                Button { speech.stop(); model.retryReply() } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                }.accessibilityLabel("重试回复").accessibilityIdentifier("retry-reply")
            }
            Menu {
                if model.canFinishConversation && !speech.isRecording {
                    Button { editing = false; model.saveConversation() } label: {
                        Label("收藏原话", systemImage: "bookmark")
                    }.disabled(!model.isLoaded || model.isSaving).accessibilityIdentifier("save-conversation")
                    Button { editing = false; model.prepareDiary() } label: {
                        Label("整理成日记", systemImage: "square.and.pencil")
                    }.accessibilityIdentifier("finish-chat")
                    Divider()
                }
                if AIFeaturePolicy.isAvailable {
                    Toggle("使用 AI", isOn: aiBinding).accessibilityIdentifier("chat-ai-toggle")
                    Button { editing = false; model.openSettings() } label: { Label("AI 设置", systemImage: "slider.horizontal.3") }
                    Divider()
                }
                Button { speech.stop(); editing = false; model.endConversation() } label: {
                    Label("先聊到这里", systemImage: "arrow.uturn.backward")
                }.accessibilityIdentifier("end-chat")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .medium))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("对话选项").accessibilityIdentifier("chat-options")
        }.foregroundStyle(MiloTheme.ink).buttonStyle(.plain)
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 10)
            .background(MiloTheme.background.opacity(0.78))
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5) }
    }

    private func messageRow(_ message: TranscriptMessage, index: Int) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 44) }
            Text(message.text).font(.body).lineSpacing(6).foregroundStyle(MiloTheme.ink.opacity(0.94))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, message.role == .user ? 17 : 0)
                .padding(.vertical, message.role == .user ? 13 : 4)
                .background {
                    if message.role == .user {
                        RoundedRectangle(cornerRadius: 22).fill(MiloTheme.accent.opacity(0.18))
                    }
                }
                .accessibilityIdentifier("message-\(index)")
            if message.role == .ai { Spacer(minLength: 28) }
        }.id(index)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if let error = speech.errorMessage {
                Text(error).font(.caption).foregroundStyle(MiloTheme.hint)
                    .accessibilityIdentifier("speech-error")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: 4) {
                Button {
                    if speech.isActive { speech.stop() }
                    else { editing = false; speechPrefix = model.draft.inputText; Task { await speech.start() } }
                } label: {
                    Image(systemName: speech.isActive ? "stop.circle.fill" : "waveform")
                        .font(.system(size: 20)).frame(width: 44, height: 44)
                }.foregroundStyle(MiloTheme.dim)
                    .accessibilityLabel(speech.isStarting ? "取消语音授权" : speech.isRecording ? "停止录音" : "语音输入")
                    .accessibilityIdentifier("speech-input")
                    .accessibilityValue(speech.isStarting ? "starting" : speech.isRecording ? "recording" : "idle")
                    .disabled(model.isThinking)
                TextField(speech.isRecording ? "正在听…" : "说说你的想法…", text: $model.draft.inputText, axis: .vertical)
                    .lineLimit(1...5).font(.body).foregroundStyle(MiloTheme.ink).focused($editing)
                    .disabled(speech.isActive).padding(.vertical, 12)
                    .accessibilityIdentifier("chat-input")
                if model.isThinking {
                    Button(action: model.stopReply) {
                        Image(systemName: "stop.fill").font(.system(size: 13))
                            .frame(width: 38, height: 38).background(.white.opacity(0.10), in: Circle())
                    }.accessibilityLabel("停止回复").accessibilityIdentifier("stop-reply")
                        .frame(width: 44, height: 44)
                } else {
                    Button { speech.stop(); model.send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(MiloTheme.background).frame(width: 38, height: 38)
                            .background(MiloTheme.dim, in: Circle())
                    }.disabled(model.draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || speech.isRecording)
                        .opacity(model.draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                        .accessibilityLabel("发送").accessibilityIdentifier("send-message")
                        .frame(width: 44, height: 44)
                }
            }.padding(.horizontal, 7).padding(.vertical, 4)
                .background(MiloTheme.surface, in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.09), lineWidth: 0.7))
        }.buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            .background(MiloTheme.background.opacity(0.96))
    }

    private var connectionDetails: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(model.aiUnavailableReason == nil ? "模型与对话" : "仅本地记录")
                        .font(MiloTheme.serif(25)).foregroundStyle(MiloTheme.ink)
                    Text(model.chatDetail ?? "对话将尝试使用你在 AI 设置中选择的模型。连接失败时会保留原话，并明确提示。").font(.body).foregroundStyle(MiloTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("chat-connection-detail")
                    Text("离开会保留草稿。收藏原话或整理日记，都由你决定。")
                        .font(.subheadline).foregroundStyle(MiloTheme.hint)
                    if model.canRetryReply {
                        MiloGlassButton(title: "重试回复") { speech.stop(); showConnection = false; model.retryReply() }
                    }
                    if AIFeaturePolicy.isAvailable {
                        MiloPrimaryButton(title: "AI 设置") { showConnection = false; model.openSettings() }
                    }
                }.padding(24)
            }.background(MiloTheme.background).navigationTitle("对话状态").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showConnection = false } } }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
    }
}

struct DiaryView: View {
    @Bindable var model: JournalModel
    @State private var editing = false
    @State private var showPreviousDiary = false
    @FocusState private var editorFocused: Bool
    private var diaryText: Binding<String> { Binding(get: { model.draft.diary ?? "" }, set: { model.editDiary($0) }) }
    private var diaryEnabled: Binding<Bool> { Binding(get: { model.draft.diaryEnabled }, set: { model.setDiaryEnabled($0) }) }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                MiloPageHeader(title: model.draft.kind == "now" ? "整理此刻" : "显影这段回忆", subtitle: "读一读，也可以改一改", back: model.back)
                if !model.guidanceNotice.isEmpty { Text(model.guidanceNotice).font(.caption).foregroundStyle(MiloTheme.dim).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(MiloTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12)) }
                Toggle(isOn: diaryEnabled) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("沉淀为日记").font(.body).foregroundStyle(MiloTheme.ink)
                        Text("关闭后只保留对话").font(.caption).foregroundStyle(MiloTheme.hint)
                    }
                }.miloPanel().accessibilityIdentifier("diary-toggle")
                if model.draft.diaryEnabled {
                    if model.isThinking {
                        HStack(spacing: 12) {
                            ProgressView().tint(MiloTheme.dim)
                            Text("回忆正在慢慢显影…").font(.subheadline).foregroundStyle(MiloTheme.dim)
                        }.frame(maxWidth: .infinity, minHeight: 150).miloPanel(padding: 24).accessibilityIdentifier("diary-generating")
                    } else { Group {
                        if editing {
                            TextField("写下这段回忆", text: diaryText, axis: .vertical).lineLimit(10...30)
                                .focused($editorFocused).accessibilityIdentifier("diary-editor")
                        } else { Text(model.draft.diary ?? "").frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).accessibilityIdentifier("diary-content") }
                    }.font(MiloTheme.serif(17, relativeTo: .body)).foregroundStyle(MiloTheme.ink).lineSpacing(14).miloPanel(padding: 24) }
                    HStack(spacing: 24) {
                        Button(editing ? "完成编辑" : "编辑日记") { editing.toggle(); editorFocused = editing }
                            .font(.body).foregroundStyle(MiloTheme.dim).frame(minHeight: 44)
                            .disabled(model.isThinking).accessibilityIdentifier("edit-diary")
                        if model.draft.previousDiary != nil {
                            Button("上一版") { editorFocused = false; showPreviousDiary = true }
                                .font(.subheadline).foregroundStyle(MiloTheme.hint).frame(minHeight: 44)
                                .disabled(model.isThinking).accessibilityIdentifier("previous-diary")
                        }
                    }
                }
            }.padding(.horizontal, 24).padding(.bottom, 28)
        }.parityScrollMetrics("journey-diary")
            .scrollDismissesKeyboard(.never)
            .safeAreaInset(edge: .bottom) {
                MiloPrimaryButton(title: "收进回忆") { editorFocused = false; editing = false; model.save() }
                    .disabled(!model.isLoaded || model.isSaving || model.isThinking).accessibilityIdentifier("save-past")
                    .padding(.horizontal, 24).padding(.vertical, 14).background(MiloTheme.background)
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成编辑") { editorFocused = false; editing = false }
                }
            }
            .sheet(isPresented: $showPreviousDiary) {
                NavigationStack {
                    ScrollView {
                        Text(model.draft.previousDiary ?? "").font(.body).lineSpacing(8).foregroundStyle(MiloTheme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(24)
                            .accessibilityIdentifier("previous-diary-content")
                    }.background(MiloTheme.background).navigationTitle("上一版日记").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showPreviousDiary = false } } }
                        .safeAreaInset(edge: .bottom) {
                            MiloGlassButton(title: "使用这一版") {
                                model.restorePreviousDiary(); editing = false; showPreviousDiary = false
                            }.accessibilityIdentifier("restore-previous-diary").padding(20).background(MiloTheme.background)
                        }
                }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
            }
            .onAppear {
                model.ensureDiary()
                #if DEBUG
                if model.account.fixtureState == "editing" { editing = true }
                #endif
            }
            .onChange(of: model.isThinking) { _, thinking in if thinking { editing = false; editorFocused = false } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 10
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 340, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, point) in result.points.enumerated() { subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified) }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var points: [CGPoint] = []
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            points.append(CGPoint(x: x, y: y)); x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
