import SwiftUI

struct AISettingsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let account: AccountModel
    let back: () -> Void
    let onSaved: () -> Void
    @State private var settings: PersonalAISettings
    @State private var apiKey = ""

    init(account: AccountModel, back: @escaping () -> Void, onSaved: @escaping () -> Void) {
        self.account = account
        self.back = back
        self.onSaved = onSaved
        _settings = State(initialValue: account.aiSettings)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                MiloBackButton { if !account.isBusy { back() } }.disabled(account.isBusy)
                Text("AI 设置").font(.title2).foregroundStyle(MiloTheme.ink)
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    enabledControl
                    Text("关闭后仅本地记录，不会回复对话；记录与导出始终可用。")
                        .font(.footnote).foregroundStyle(MiloTheme.hint)
                    sourceLayout {
                        sourceButton("自己的模型", source: .personal)
                        sourceButton("MILO 默认模型（未接通）", source: .milo)
                    }
                    if settings.source == .personal { personalSettings } else { hostedSettings }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20).disabled(account.isBusy)
            }.parityScrollMetrics("account-ai-settings")
                .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            AccountStatusView(account: account)
            MiloPrimaryButton(title: "保存设置") {
                if account.saveAISettings(settings, newKey: apiKey) {
                    apiKey = ""
                    settings = account.aiSettings
                    onSaved()
                }
            }.disabled(account.isBusy).accessibilityIdentifier("ai-save")
        }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            .onDisappear { apiKey = "" }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page-ai-settings")
    }

    @ViewBuilder private var enabledControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text("默认开启 AI").font(.body).foregroundStyle(MiloTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("默认开启 AI", isOn: $settings.enabled).labelsHidden().tint(MiloTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("ai-enabled")
            }
        } else {
            Toggle("默认开启 AI", isOn: $settings.enabled)
                .font(.body).foregroundStyle(MiloTheme.ink).tint(MiloTheme.accent)
                .accessibilityIdentifier("ai-enabled")
        }
    }
    private var sourceLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private var personalSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务商").font(.body).foregroundStyle(MiloTheme.ink)
            Menu {
                ForEach(AIProvider.allCases) { provider in
                    Button(provider.title) { selectProvider(provider) }
                }
            } label: {
                HStack {
                    Text(settings.provider.title).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption).fixedSize()
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(MiloTheme.ink).padding(16)
                    .background(MiloTheme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            }.accessibilityIdentifier("ai-provider")
            Text("接口地址（Base URL 或完整 /chat/completions 地址）")
                .font(.footnote).foregroundStyle(MiloTheme.hint)
            TextField("https://api.example.com/v1", text: $settings.baseURL, axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().miloAccountField()
                .accessibilityIdentifier("ai-base-url")
                .onChange(of: settings.baseURL) { _, _ in settings.consent = false; apiKey = ""; account.clearMessages() }
            TextField("模型名称，例如 qwen-plus", text: $settings.model, axis: dynamicTypeSize.isAccessibilitySize ? .vertical : .horizontal)
                .textInputAutocapitalization(.never).autocorrectionDisabled().miloAccountField()
                .accessibilityIdentifier("ai-model")
            SecureField(account.hasAPIKey(for: settings) ? "已安全保存 Key（输入可替换）" : "API Key", text: $apiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().miloAccountField()
                .accessibilityIdentifier("ai-api-key")
            Text("支持 OpenAI 兼容 Chat Completions 接口。服务商默认地址可编辑；地区或套餐不同，请使用控制台给出的地址和模型名称。")
                .font(.caption).foregroundStyle(MiloTheme.hint).lineSpacing(6)
            consentRow("我同意将当前情绪和对话发送到上述地址；费用由该服务商按我的 Key 计费。")
            Text("Key 仅保存于本设备系统安全存储，不经过 MILO 服务器，也不会包含在日记导出中。连接测试只发送一条测试问候，可能产生少量用量。")
                .font(.caption).foregroundStyle(MiloTheme.hint).lineSpacing(6)
            Button(account.isBusy ? "正在测试…" : "测试连接") {
                Task { await account.testConnection(settings: settings, newKey: apiKey) }
            }.font(.subheadline).foregroundStyle(MiloTheme.dim).frame(minHeight: 44)
                .accessibilityIdentifier("ai-test-connection")
            Button("删除已保存的 Key") {
                account.removeAPIKey(for: settings); apiKey = ""; settings.consent = false
            }.font(.subheadline).foregroundStyle(MiloTheme.hint).frame(minHeight: 44)
                .accessibilityIdentifier("ai-delete-key")
        }
    }
    private var hostedSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("默认由 MILO 后台调用 MiniMax，无需填写个人 Key。MiniMax 密钥仅保存在服务器。")
                .font(.subheadline).foregroundStyle(MiloTheme.dim).lineSpacing(7)
            Text("尚未接通：此安装包缺少后台公网 HTTPS 地址。")
                .font(.footnote).foregroundStyle(MiloTheme.hint).accessibilityIdentifier("ai-hosted-unavailable")
            consentRow("我同意将当前情绪和对话经 MILO 后台发送给 MiniMax，用于生成回复和日记；不会发送全部历史日记。")
            VStack(alignment: .leading, spacing: 14) {
                Text("MILO 星球会员").font(MiloTheme.serif(22)).foregroundStyle(MiloTheme.ink)
                Text("月订阅方案 · 拟定 ¥12 / 月").font(.title3).foregroundStyle(MiloTheme.dim)
                Text("计划权益：每月 300 次 AI 回复或日记生成。无需自己配置 Key。额度用尽仍可本地记录，或切换自己的模型。")
                    .font(.subheadline).foregroundStyle(MiloTheme.dim).lineSpacing(7)
                Text("订阅筹备中，暂不收费。正式开通前会展示最终价格、额度、续费与取消说明。")
                    .font(.footnote).foregroundStyle(MiloTheme.hint).lineSpacing(6)
                MiloGlassButton(title: "订阅暂未开放") {}.disabled(true).opacity(0.5)
            }.miloPanel(padding: 18)
        }
    }
    private func consentRow(_ title: String) -> some View {
        Button { settings.consent.toggle() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: settings.consent ? "checkmark.square.fill" : "square")
                    .font(.system(size: 23)).foregroundStyle(settings.consent ? MiloTheme.accent : MiloTheme.hint)
                    .frame(width: 28, height: 28)
                Text(title).font(.footnote).lineSpacing(5).foregroundStyle(MiloTheme.dim).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("ai-consent")
            .accessibilityValue(settings.consent ? "已同意" : "未同意")
    }
    private func sourceButton(_ title: String, source: PersonalAISettings.Source) -> some View {
        Button {
            if settings.source != source { settings.consent = false; apiKey = ""; account.clearMessages() }
            settings.source = source
        } label: {
            Text(title).font(.footnote).foregroundStyle(MiloTheme.ink)
                .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.center)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 16 : 0)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(settings.source == source ? MiloTheme.accent.opacity(0.65) : MiloTheme.accent.opacity(0.16), in: Capsule())
        }.accessibilityIdentifier(source == .personal ? "ai-source-personal" : "ai-source-hosted")
    }
    private func selectProvider(_ provider: AIProvider) {
        guard settings.provider != provider else { return }
        settings.provider = provider; settings.baseURL = provider.baseURL; settings.model = provider.model
        settings.consent = false; apiKey = ""; account.clearMessages()
        account.statusMessage = "已切换服务商，请填写对应 Key。"
    }
}
