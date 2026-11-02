import SwiftUI
import PhotosUI
import MiloCore

struct AccountView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let account: AccountModel
    let entryCount: Int
    let exportJSON: () -> Data?
    let exportMarkdown: () -> String?
    let onAISettings: () -> Void
    let onLogout: () -> Void
    let onDeleteLocalData: () -> Bool
    let back: () -> Void
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var passwordOpen = false
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var showLogout = false
    @State private var showDelete = false
    @State private var shareDocument: AccountShareDocument?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                MiloBackButton(action: back)
                Text("我的").font(.title2).foregroundStyle(MiloTheme.ink)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profile
                    securityPanel
                    if AIFeaturePolicy.isAvailable {
                        VStack(alignment: .leading, spacing: 10) {
                            panelTitle("AI 与会员")
                            Text("连接自己的大模型，或了解 MILO 星球会员。")
                                .font(.footnote).foregroundStyle(MiloTheme.dim)
                            accountLink("AI 设置与月订阅方案  ›", identifier: "account-ai-settings") {
                                account.clearMessages(); onAISettings()
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).miloPanel(padding: 18)
                    }
                    dataPanel
                    Text("MILO 米洛 · 留住每一份感受").font(.caption).foregroundStyle(MiloTheme.hint)
                        .frame(maxWidth: .infinity).padding(.bottom, 12)
                }
            }.parityScrollMetrics("account-profile")
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            AccountStatusView(account: account)
            MiloPrimaryButton(title: "退出登录") { showLogout = true }
                .disabled(account.isBusy).accessibilityIdentifier("account-logout")
            Button("注销账号") { showDelete = true }
                .font(.footnote).foregroundStyle(MiloTheme.hint).frame(minHeight: 44)
                .disabled(account.isBusy).accessibilityIdentifier("account-delete")
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
            .alert("退出登录？", isPresented: $showLogout) {
                Button("取消", role: .cancel) {}
                Button("退出登录") { Task { if await account.signOut() { onLogout() } } }
            } message: { Text("本机回忆会保留，再次使用时需要登录。") }
            .alert("注销账号？", isPresented: $showDelete) {
                Button("取消", role: .cancel) {}
                Button("注销并删除", role: .destructive) {
                    Task { if await account.deleteAccount(deleteLocalData: onDeleteLocalData) { onLogout() } }
                }
            } message: { Text("将注销 MILO 账号，并删除此设备的日记和草稿，无法恢复。已保存到相册的图片不会删除。") }
            .sheet(item: $shareDocument, onDismiss: cleanupShare) { document in
                AccountShareSheet(url: document.url) { completed in
                    account.statusMessage = completed ? "已完成分享或导出。" : "已取消导出，原回忆已保留。"
                }.presentationDetents([.medium, .large])
            }
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                loadingPhoto = true
                Task {
                    defer { loadingPhoto = false; selectedPhoto = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                        _ = account.setAvatar(data)
                    } catch { account.errorMessage = "头像未更新，请选择可读取且小于 20 MB 的图片。" }
                }
            }
            .onAppear(perform: applyFixture)
            .onDisappear { code = ""; password = ""; confirmation = "" }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page-account")
    }

    private var profile: some View {
        let savedAvatar = account.avatarData
        let photoBusy = loadingPhoto
        return VStack(spacing: 10) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                VStack(spacing: 10) {
                    Group {
                        if let data = savedAvatar, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(Circle())
                        } else { MoodPlanet(mood: .okay, size: 84).frame(width: 84, height: 84).clipped() }
                    }.frame(width: 84, height: 84)
                    Text(photoBusy ? "正在更新…" : "更换头像").font(.footnote).foregroundStyle(MiloTheme.dim)
                }.contentShape(Rectangle())
            }.disabled(account.isBusy || loadingPhoto).accessibilityIdentifier("account-avatar")
            if account.avatarData != nil {
                Button("恢复星球头像") { account.resetAvatar() }.font(.caption).foregroundStyle(MiloTheme.hint).frame(minHeight: 44)
            }
            Text(account.email).font(.headline.weight(.regular)).foregroundStyle(MiloTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
            Text("已收藏 \(entryCount) 段回忆").font(.footnote).foregroundStyle(MiloTheme.hint)
        }.frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 8)
    }
    private var securityPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelTitle("账号与安全").padding(.bottom, 8)
            infoRow("登录方式", value: account.isLocalAccount ? "本地体验账号" : "邮箱登录", identifier: "account-login-method")
            infoRow("绑定邮箱", value: account.isLocalAccount ? "未绑定" : account.email, identifier: "account-bound-email")
            if account.isLocalAccount {
                Text("本地体验账号无需密码。使用邮箱账号登录后可管理密码。")
                    .font(.caption).foregroundStyle(MiloTheme.hint).lineSpacing(6)
            } else {
                Button {
                    passwordOpen.toggle(); code = ""; password = ""; confirmation = ""; account.clearMessages()
                } label: {
                    accountRowLayout {
                        Text("修改密码").font(.subheadline).foregroundStyle(MiloTheme.ink)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Text(passwordOpen ? "收起  ⌃" : "邮箱验证  ›").font(.footnote).foregroundStyle(MiloTheme.hint)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }.accessibilityIdentifier("account-password-toggle")
            }
            if passwordOpen { passwordForm.padding(.top, 12) }
        }.frame(maxWidth: .infinity, alignment: .leading).miloPanel(padding: 18)
    }
    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("邮箱验证码", text: feedbackInput($code)).keyboardType(.numberPad).textContentType(.oneTimeCode).miloAccountField()
                .onChange(of: code) { _, value in code = String(value.filter { "0123456789".contains($0) }.prefix(6)) }
                .accessibilityIdentifier("account-password-code")
            SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in
                let seconds = account.resendSeconds(email: account.email, purpose: .resetPassword)
                Button(seconds > 0 ? "\(seconds) 秒后重发" : "发送验证码") {
                    Task { _ = await account.requestCode(email: account.email, purpose: .resetPassword) }
                }.font(.footnote).foregroundStyle(MiloTheme.dim).frame(minHeight: 44).disabled(seconds > 0 || account.isBusy)
            }
            MiloSecureField("新密码", text: feedbackInput($password), identifier: "account-new-password", contentType: .newPassword)
            MiloSecureField("再次输入新密码", text: feedbackInput($confirmation), identifier: "account-confirm-password", contentType: .newPassword)
            Text("密码为 6–32 位，首尾不留空格。最终要求以账号服务设置为准。")
                .font(.caption).foregroundStyle(MiloTheme.hint)
            MiloPrimaryButton(title: account.isBusy ? "请稍候…" : "保存新密码") {
                Task {
                    if await account.changePassword(code: code, password: password, confirmation: confirmation) {
                        code = ""; password = ""; confirmation = ""; passwordOpen = false
                    }
                }
            }.disabled(account.isBusy)
        }
    }
    private func feedbackInput(_ value: Binding<String>) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { next in
            guard value.wrappedValue != next else { return }
            value.wrappedValue = next; account.clearMessages()
        })
    }
    private var dataPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            panelTitle("回忆与数据")
            Text("导出全部情绪、日记与对话，保存在你选择的位置。导出内容不含账号密码或 API Key。")
            accountLink("导出 Markdown（方便阅读）", identifier: "account-export-markdown") { prepareExport(markdown: true) }
            accountLink("导出 JSON（完整数据）", identifier: "account-export-json") { prepareExport(markdown: false) }
            Text("日记和草稿保存在当前设备，暂不支持账号间同步。退出登录不会删除本机回忆。")
            Text("注销账号会同时删除本机日记与草稿，请提前保存想留下的回忆卡片。")
        }.font(.footnote).foregroundStyle(MiloTheme.dim).lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .leading).miloPanel(padding: 18)
    }
    private func panelTitle(_ title: String) -> some View { Text(title).font(.footnote).foregroundStyle(MiloTheme.dim) }
    private var accountRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }
    private func infoRow(_ title: String, value: String, identifier: String) -> some View {
        accountRowLayout {
            Text(title).foregroundStyle(MiloTheme.dim).fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
            Text(value).foregroundStyle(MiloTheme.ink)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1).truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(identifier)-value")
        }.font(.subheadline).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .multilineTextAlignment(.leading)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
    }
    private func accountLink(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.footnote).foregroundStyle(MiloTheme.dim).frame(minHeight: 44, alignment: .leading) }
            .buttonStyle(.plain).disabled(account.isBusy).accessibilityIdentifier(identifier)
    }
    private func prepareExport(markdown: Bool) {
        account.clearMessages()
        let data = markdown ? exportMarkdown().map { Data($0.utf8) } : exportJSON()
        guard let data else { account.errorMessage = "导出失败，原回忆已保留，请重试。"; return }
        let directory = JournalModel.temporaryExportDirectory(for: account.directory).appendingPathComponent("MILO-Export-\(UUID().uuidString)")
        let url = directory.appendingPathComponent(markdown ? "MILO-回忆.md" : "MILO-回忆.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            shareDocument = AccountShareDocument(url: url)
        } catch { account.errorMessage = "导出失败，请检查存储空间并重试；原回忆已保留。" }
    }
    private func cleanupShare() {
        if let url = shareDocument?.url { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        shareDocument = nil
    }
    private func applyFixture() {
        #if DEBUG
        if account.fixtureState == "password-form" { passwordOpen = true }
        if account.fixtureState == "delete-confirmation" { showDelete = true }
        #endif
    }
}

struct AccountStatusView: View {
    let account: AccountModel
    var body: some View {
        if !account.statusMessage.isEmpty {
            Text(account.statusMessage).font(.footnote).foregroundStyle(MiloTheme.dim).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("account-status")
        }
        if !account.errorMessage.isEmpty {
            Text(account.errorMessage).font(.footnote).foregroundStyle(Color(red: 0.94, green: 0.69, blue: 0.69))
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("account-error")
        }
    }
}

private struct AccountShareDocument: Identifiable { let id = UUID(); let url: URL }
private struct AccountShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completed: (Bool) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, didComplete, _, _ in
            Task { @MainActor in completed(didComplete) }
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
