import SwiftUI
import MiloCore

struct JournalView: View {
    @Bindable var model: JournalModel
    @State private var galaxy = MiloGalaxyState()
    var body: some View {
        GeometryReader { viewport in
            ZStack {
                MiloBackground(galaxy: galaxy)
                Group {
                    if !model.account.isAuthenticated {
                        LoginView(account: model.account, onAuthenticated: {})
                    } else {
                        page
                    }
                }
                .frame(width: viewport.size.width, height: viewport.size.height)
                .clipped()
            }
            #if DEBUG
            if ParityFixture.caseID != nil {
                let frame = viewport.frame(in: .global)
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Safe viewport")
                    .accessibilityIdentifier("parity-viewport")
                    .accessibilityValue("{\"frameX\":\(frame.minX),\"frameY\":\(frame.minY),\"frameWidth\":\(frame.width),\"frameHeight\":\(frame.height)}")
                    .allowsHitTesting(false)
            }
            #endif
        }.tint(MiloTheme.accent).preferredColorScheme(.dark)
            .alert("MILO", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("知道了") { model.errorMessage = nil }
                if model.hasDraftRecoveryConflict {
                    Button("继续当前，备份旧草稿") { model.resolveDraftRecovery(keepCurrent: true) }
                    Button("恢复旧草稿，备份当前") { model.resolveDraftRecovery(keepCurrent: false) }
                } else {
                    Button("重试") { model.retryStorage() }
                }
            } message: { Text(model.errorMessage ?? "") }
    }
    @ViewBuilder private var page: some View {
        switch model.draft.page {
        case "home", "home-words", "words": HomeView(model: model)
        case "classify": ClassifyView(model: model)
        case "now-note": NowNoteView(model: model)
        case "past-time": PastTimeView(model: model)
        case "chat": ChatView(model: model)
        case "diary": DiaryView(model: model)
        case "timeline": TimelineView(entries: model.entries, onSelect: model.openEntry, back: model.returnHome)
        case "detail": MemoryDetailView(entry: model.selectedEntry, onDelete: model.deleteSelected, onCard: { model.go("card") }, back: { model.go("timeline") })
        case "card":
            if let entry = model.selectedEntry {
                MemoryCardView(entry: entry, temporaryExportDirectory: model.temporaryExportDirectory, onTemplate: model.setTemplate, onDone: { model.go("timeline") }, onHome: model.startHome, back: { model.go("timeline") })
            } else { MemoryDetailView(entry: nil, onDelete: {}, onCard: {}, back: { model.go("timeline") }) }
        case "account": AccountView(account: model.account, entryCount: model.entries.count, exportJSON: model.exportJSON, exportMarkdown: model.exportMarkdown, onAISettings: model.openSettings, onLogout: model.logout, onDeleteLocalData: model.clearLocalData, back: model.returnHome)
        case "ai-settings":
            if AIFeaturePolicy.isAvailable {
                AISettingsView(account: model.account, back: model.back, onSaved: model.aiSettingsDidSave)
            } else {
                VStack(spacing: 24) {
                    Text("AI 功能暂时下架").font(.title2).foregroundStyle(MiloTheme.ink)
                    Text(AIFeaturePolicy.pausedMessage).foregroundStyle(MiloTheme.dim)
                    MiloPrimaryButton(title: "继续本地记录") {
                        if model.hasUnfinishedDraft { model.resumeDraft() } else { model.returnHome() }
                    }
                }.padding(24).accessibilityIdentifier("page-ai-paused")
            }
        default: HomeView(model: model)
        }
    }
}
