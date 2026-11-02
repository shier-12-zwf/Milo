import SwiftUI
import Photos
import UIKit
import MiloCore

struct MemoryCardView: View {
    let entry: JournalEntry
    let temporaryExportDirectory: URL
    let onTemplate: (CardTemplate) -> Void
    let onDone: () -> Void
    let onHome: () -> Void
    let back: () -> Void
    @State private var selected: CardTemplate
    @State private var hasChangedTemplate = false
    @State private var saveState: CardSaveState = .idle
    @State private var share: CardShareFile?
    @State private var shareFailure: String?

    init(entry: JournalEntry, temporaryExportDirectory: URL, onTemplate: @escaping (CardTemplate) -> Void,
         onDone: @escaping () -> Void, onHome: @escaping () -> Void, back: @escaping () -> Void) {
        self.entry = entry
        self.temporaryExportDirectory = temporaryExportDirectory
        self.onTemplate = onTemplate
        self.onDone = onDone
        self.onHome = onHome
        self.back = back
        _selected = State(initialValue: entry.stickerTemplate)
    }

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button(action: onDone) {
                            Label("完成", systemImage: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                        .accessibilityIdentifier("card-done")
                        Spacer()
                        Button(action: prepareShare) {
                            Image(systemName: "square.and.arrow.up").font(.body)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .accessibilityLabel("分享卡片").accessibilityIdentifier("share-card")
                        .disabled(saveState.isSaving)
                    }
                    .buttonStyle(.plain).foregroundStyle(MiloTheme.dim)
                    .padding(.bottom, 4)
                    VStack(spacing: 7) {
                        Text("MILO MEMORY").font(.system(size: 12)).tracking(4)
                            .foregroundStyle(MiloTheme.dim.opacity(0.65))
                        Text("你的情绪卡片")
                            .font(MiloTheme.serif(27)).fontWeight(.medium)
                            .foregroundStyle(MiloTheme.ink)
                        Text("把这颗星球，分享给今天的世界。")
                            .font(.subheadline).foregroundStyle(MiloTheme.dim)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity).padding(.bottom, 30)

                    CardArtworkView(entry: entry, template: selected)
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                        .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(.white.opacity(0.11)))
                        .shadow(color: MiloTheme.accent.opacity(0.14), radius: 28)
                        .frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("card.preview")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                            if hasChangedTemplate {
                                scrollToTemplates(scroll)
                            }
                        }
                        .padding(.bottom, 32)
                    VStack(spacing: 0) {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("LAYOUTS").font(.system(size: 9)).tracking(1.8)
                                    .foregroundStyle(MiloTheme.dim.opacity(0.65))
                                Text("选择卡片模板")
                                    .font(MiloTheme.serif(16)).fontWeight(.medium)
                                    .foregroundStyle(MiloTheme.ink)
                            }
                            Spacer()
                            Text(selected == .planetLetter ? "1 / 2" : "2 / 2")
                                .font(.caption2.monospaced()).tracking(1.8)
                                .foregroundStyle(MiloTheme.dim.opacity(0.65))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("card-templates-heading")
                        .padding(.horizontal, 2).padding(.bottom, 11)
                        CardTemplateColumns(spacing: 10) {
                            templateButton(.planetLetter, index: 1)
                            templateButton(.orbitTheatre, index: 2)
                        }
                        // A template changes the artwork height above this row.
                        // Selection feedback must never animate row placement.
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
                    // Keep a physical margin above fixed actions, including
                    // fractional-point layout rounding after template changes.
                    .padding(.bottom, 8)
                    .id("card-template-region")
                }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 20)
            }
            .parityScrollMetrics("collection-card")
            .scrollIndicators(.hidden)
            .onChange(of: selected) { _, _ in
                // Artwork heights differ. Keep the complete selector in the safe
                // scroll viewport after the new template's layout is committed.
                scrollToTemplates(scroll)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .onChange(of: entry.id) { _, _ in
            hasChangedTemplate = false
            selected = entry.stickerTemplate
            saveState = .idle
        }
        .onDisappear { CardArtworkRaster.clear() }
        .sheet(item: $share, onDismiss: clearShareFile) { file in
            CardActivitySheet(url: file.url)
                .presentationDetents([.medium, .large])
                .accessibilityIdentifier("card-share-sheet")
        }
        .alert("暂时无法分享", isPresented: Binding(get: { shareFailure != nil }, set: { if !$0 { shareFailure = nil } })) {
            Button("好", role: .cancel) { shareFailure = nil }
        } message: { Text(shareFailure ?? "") }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("card.page")
    }

    private func scrollToTemplates(_ scroll: ScrollViewProxy) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scroll.scrollTo("card-template-region", anchor: .bottom)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let message = saveState.message {
                Text(message).font(.caption)
                    .foregroundStyle(saveState.isFailure ? Color(red: 0.96, green: 0.77, blue: 0.83) : MiloTheme.dim)
                    .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.bottom, 8)
                    .accessibilityIdentifier("card.save-status")
            }
            HStack(spacing: 12) {
                MiloGlassButton(title: saveState.isSaving ? "正在保存…" : "保存图片", action: saveImage)
                    .disabled(saveState.isSaving).accessibilityIdentifier("save-card")
                MiloPrimaryButton(title: "回到首页", action: onHome)
                    .accessibilityIdentifier("card-home")
            }
            .padding(10)
            .background(Color(red: 0.027, green: 0.027, blue: 0.071).opacity(0.90), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MiloTheme.dim.opacity(0.14)))
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .background(MiloTheme.background.opacity(0.96))
    }

    private func templateButton(_ template: CardTemplate, index: Int) -> some View {
        Button {
            guard !saveState.isSaving else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasChangedTemplate = true
                selected = template
                saveState = .idle
                onTemplate(template)
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                CardTemplatePreviewBounds {
                    Image(uiImage: CardArtworkRaster.thumbnail(entry: entry, template: template))
                        .resizable()
                }
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(alignment: .topLeading) {
                        Text(String(format: "%02d", index)).font(.system(size: 8).monospaced())
                            .foregroundStyle(.white.opacity(0.76))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.48), in: Capsule())
                            .overlay(Capsule().strokeBorder(.white.opacity(0.16)))
                            .padding(5)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("\(template.title)预览")
                    .accessibilityIdentifier("card-template-preview-\(template.rawValue)")
                Text(template.title).font(MiloTheme.serif(14, relativeTo: .subheadline))
                    .foregroundStyle(MiloTheme.ink).padding(.top, 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("card-template-title-\(template.rawValue)")
                Text(template.subtitle).font(.caption).foregroundStyle(MiloTheme.dim.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("card-template-subtitle-\(template.rawValue)")
            }
            .padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [MiloTheme.accent.opacity(selected == template ? 0.19 : 0.07), MiloTheme.surface.opacity(0.78)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(selected == template ? Color(red: 0.73, green: 0.67, blue: 1).opacity(0.72) : .white.opacity(0.10)))
        }
        .buttonStyle(CardTemplateSelectionStyle())
        .accessibilityLabel("\(template.title)，\(template.subtitle)")
        .accessibilityAddTraits(selected == template ? [.isSelected] : [])
        .accessibilityIdentifier("card-template-\(template.rawValue)")
    }

    @MainActor private func pngData() throws -> Data {
        guard let data = CardArtworkRaster.image(entry: entry, template: selected).pngData() else {
            throw CardExportError.renderFailed
        }
        return data
    }

    private func saveImage() {
        guard !saveState.isSaving else { return }
        saveState = .saving
        Task { @MainActor in
            do {
                let data = try pngData()
                let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard permission == .authorized || permission == .limited else {
                    saveState = .failed("未获得相册保存权限。你仍可以通过右上角分享按钮保存卡片。")
                    return
                }
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    let options = PHAssetResourceCreationOptions()
                    options.originalFilename = "milo-\(UUID().uuidString).png"
                    request.addResource(with: .photo, data: data, options: options)
                }
                saveState = .saved
            } catch {
                saveState = .failed("保存失败，请重试。你的回忆仍保存在米洛里。")
            }
        }
    }

    private func prepareShare() {
        do {
            let data = try pngData()
            let directory = temporaryExportDirectory.appendingPathComponent("MiloCardShares", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("milo-\(UUID().uuidString).png")
            try data.write(to: url, options: .atomic)
            share = CardShareFile(url: url)
        } catch { shareFailure = "卡片生成失败，请稍后重试。" }
    }

    private func clearShareFile() {
        // The system share sheet may retain the URL while handing it to another
        // application. The operating system owns this temporary cache's lifetime.
        share = nil
    }
}

/// The thumbnail owns its height independently of the enclosing equal-height
/// button proposal. A flexible image must not consume the title/subtitle space
/// when the full card above it changes height during a real template switch.
private struct CardTemplatePreviewBounds: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 144
        return CGSize(width: width, height: width / 1.6)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: bounds.width / 1.6))
        }
    }
}

/// Propose one measured height and one width to both buttons, including their
/// image, title, subtitle and padding. This also equalizes their tappable bounds.
private struct CardTemplateColumns: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 320
        let columnWidth = max(0, (width - spacing) / 2)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = max(0, (bounds.width - spacing) / 2)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

private enum CardSaveState: Equatable {
    case idle, saving, saved, failed(String)
    var isSaving: Bool { self == .saving }
    var isFailure: Bool { if case .failed = self { return true }; return false }
    var message: String? {
        switch self {
        case .idle: nil
        case .saving: "正在保存…"
        case .saved: "已保存到系统相册。"
        case .failed(let message): message
        }
    }
}

private enum CardExportError: Error { case renderFailed }
private struct CardShareFile: Identifiable {
    let id = UUID()
    let url: URL
}
private struct CardActivitySheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Opacity changes immediately. An unscoped `.animation(value: isPressed)`
/// would also animate the label's layout when selection and release coincide.
private struct CardTemplateSelectionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.82 : 1)
    }
}
