import SwiftUI
import MiloCore

struct TimelineView: View {
    let entries: [JournalEntry]
    let onSelect: (String) -> Void
    let back: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MiloBackButton(action: back)
                Spacer(minLength: 0)
                Text("回忆长廊").font(.subheadline).foregroundStyle(MiloTheme.dim)
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            .padding(.horizontal, 20).padding(.top, 8)
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Text("这里还很安静")
                        .font(MiloTheme.serif(22)).fontWeight(.medium)
                        .foregroundStyle(MiloTheme.ink)
                    Text("当你收藏了第一段感受，\n它就会在这里亮起来。")
                        .font(.subheadline).lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(MiloTheme.hint)
                }
                .padding(.top, 120).padding(.horizontal, 24)
                .accessibilityIdentifier("timeline.empty")
                Spacer(minLength: 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in
                            Button { onSelect(entry.id) } label: { row(entry) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("timeline.entry.\(entry.id)")
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
                }
                .parityScrollMetrics("collection-timeline")
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("timeline.page")
    }

    private func row(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(MiloTheme.accent).frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(CollectionDate.short(entry.createdAt))
                            .font(.caption).foregroundStyle(MiloTheme.hint)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    timeMark(entry)
                }
            } else {
                HStack(spacing: 8) {
                    Circle().fill(MiloTheme.accent).frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(CollectionDate.short(entry.createdAt))
                        .font(.caption).foregroundStyle(MiloTheme.hint).lineLimit(1)
                    Spacer(minLength: 4)
                    timeMark(entry)
                }
            }
            Text(entry.mood.title).font(.subheadline.weight(.medium))
                .foregroundStyle(MiloTheme.ink).lineLimit(1)
            Text(entry.preview).font(.subheadline).lineSpacing(3)
                .foregroundStyle(MiloTheme.dim).lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? 156 : 132, alignment: .topLeading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    private func timeMark(_ entry: JournalEntry) -> some View {
        Text(entry.kind == "past" ? (entry.timeMark ?? "过去") : "此刻")
            .font(.caption2).foregroundStyle(MiloTheme.dim)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(MiloTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 116,
                   alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
    }
}

enum CollectionDate {
    static func short(_ milliseconds: Double) -> String {
        format(milliseconds, pattern: "M 月 d 日 HH:mm")
    }
    static func full(_ milliseconds: Double) -> String {
        format(milliseconds, pattern: "yyyy 年 M 月 d 日")
    }
    static func archive(_ milliseconds: Double) -> String {
        format(milliseconds, pattern: "yyyy.MM.dd")
    }
    private static func format(_ milliseconds: Double, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = pattern
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }
}
