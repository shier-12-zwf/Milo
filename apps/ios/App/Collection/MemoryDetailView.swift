import SwiftUI
import MiloCore

struct MemoryDetailView: View {
    let entry: JournalEntry?
    let onDelete: () -> Void
    let onCard: () -> Void
    let back: () -> Void
    @State private var showTranscript = false
    @State private var confirmDelete = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: back) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("返回回忆长廊")
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize || entry == nil {
                    Text(entry.map { CollectionDate.full($0.createdAt) } ?? "回忆")
                        .font(.caption).foregroundStyle(MiloTheme.dim).lineLimit(1)
                        .accessibilityIdentifier("detail-date")
                    Spacer(minLength: 0)
                }
                Button("放下") { confirmDelete = true }
                    .font(.subheadline).foregroundStyle(MiloTheme.hint)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(entry == nil)
                    .accessibilityIdentifier("delete-memory")
            }
            .buttonStyle(.plain).foregroundStyle(MiloTheme.dim)
            .padding(.horizontal, 16).padding(.top, 8)

            if let entry {
                ScrollView {
                    VStack(spacing: 0) {
                        if typeSize.isAccessibilitySize {
                            Text(CollectionDate.full(entry.createdAt))
                                .font(.caption).foregroundStyle(MiloTheme.dim)
                                .lineLimit(nil)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 24).padding(.top, 12)
                                .accessibilityIdentifier("detail-date")
                        }
                        Text(entry.kind == "past" ? (entry.timeMark ?? "过去的某一天") : "此刻")
                            .font(MiloTheme.serif(24)).fontWeight(.medium)
                            .foregroundStyle(MiloTheme.ink).padding(.top, 16)
                        Text(moodSummary(entry))
                            .font(.subheadline).foregroundStyle(MiloTheme.hint)
                            .multilineTextAlignment(.center).padding(.top, 6).padding(.horizontal, 24)
                        MoodPlanet(mood: entry.mood, size: 110)
                            .padding(.top, 24).accessibilityHidden(true)
                        if !content(entry).isEmpty {
                            Text(content(entry)).font(.body).lineSpacing(7)
                                .textSelection(.enabled).foregroundStyle(MiloTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(18)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 24))
                                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.08)))
                                .padding(.horizontal, 20).padding(.top, 24)
                                .accessibilityIdentifier("detail.content")
                        }
                        if !entry.transcript.isEmpty {
                            Button(showTranscript ? "收起当时的对话" : "看看当时的对话") {
                                withAnimation(.easeInOut(duration: 0.2)) { showTranscript.toggle() }
                            }
                            .font(.subheadline).foregroundStyle(MiloTheme.dim)
                            .frame(minHeight: 44).padding(.top, 12)
                            .accessibilityIdentifier("toggle-transcript")
                            if showTranscript {
                                transcript(entry).padding(.horizontal, 20).padding(.top, 8)
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .parityScrollMetrics("collection-detail")
                .scrollIndicators(.hidden)
                MiloPrimaryButton(title: "生成回忆卡片", action: onCard)
                    .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 24)
                    .accessibilityIdentifier("open-card")
            } else {
                Text("这段回忆已经飘走了。")
                    .foregroundStyle(MiloTheme.hint).padding(.top, 100)
                Spacer()
            }
        }
        .alert("放下这段回忆？", isPresented: $confirmDelete) {
            Button("再留一会儿", role: .cancel) {}
            Button("放下回忆", role: .destructive, action: onDelete)
                .accessibilityIdentifier("confirm-delete")
        } message: {
            Text("这会从这台设备删除这段回忆，无法撤销。")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.page")
        .onAppear {
            #if DEBUG
            if ParityFixture.state == "transcript-expanded" { showTranscript = true }
            if ParityFixture.state == "delete-confirmation", entry != nil { confirmDelete = true }
            #endif
        }
    }

    private func moodSummary(_ entry: JournalEntry) -> String {
        var seen = Set<String>()
        return ([entry.mood.title] + entry.labels).filter { seen.insert($0).inserted }.joined(separator: " · ")
    }

    private func content(_ entry: JournalEntry) -> String {
        if let diary = entry.diary, !diary.isEmpty { return diary }
        return entry.note
    }

    private func transcript(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(entry.transcript.enumerated()), id: \.offset) { _, message in
                HStack {
                    if message.role == .user { Spacer(minLength: 34) }
                    Text(message.text).font(.subheadline).lineSpacing(5)
                        .textSelection(.enabled).foregroundStyle(MiloTheme.ink)
                        .padding(12)
                        .background(message.role == .user ? MiloTheme.accent.opacity(0.20) : .white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityLabel("\(message.role == .user ? "我" : "米洛")：\(message.text)")
                    if message.role != .user { Spacer(minLength: 34) }
                }
            }
        }
    }
}
