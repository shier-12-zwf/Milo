import SwiftUI

struct LoginView: View {
    let account: AccountModel
    let onAuthenticated: () -> Void
    private enum Step { case email, code, resetEmail, reset }
    private enum Mode { case code, password }
    @State private var step: Step = .email
    @State private var mode: Mode = .code
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var newPassword = ""
    @FocusState private var focused: Field?
    private enum Field { case email, code, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    if step != .email { MiloBackButton { backToEmail() }.disabled(account.isBusy) }
                    Spacer()
                }.frame(height: 44)
                Text("MILO").font(.system(size: 36, weight: .medium, design: .serif)).tracking(6)
                    .foregroundStyle(MiloTheme.ink).padding(.top, 32).padding(.bottom, 36)
                Text(title).font(.title2.weight(.medium)).foregroundStyle(MiloTheme.ink).padding(.bottom, 24)
                if step == .email { modeSelector.padding(.bottom, 24) }
                if step == .code || step == .reset {
                    Text("已发送至 \(email.trimmingCharacters(in: .whitespacesAndNewlines))")
                        .font(.subheadline).foregroundStyle(MiloTheme.hint).multilineTextAlignment(.center).padding(.bottom, 24)
                    TextField("6 位验证码", text: feedbackInput($code))
                        .keyboardType(.numberPad).textContentType(.oneTimeCode).multilineTextAlignment(.center)
                        .font(.title2).miloAccountField().focused($focused, equals: .code)
                        .accessibilityIdentifier("login-code")
                        .onChange(of: code) { _, value in code = String(value.filter { "0123456789".contains($0) }.prefix(6)) }
                    if step == .reset { passwordField(reset: true).padding(.top, 14) }
                } else {
                    TextField("邮箱地址", text: emailInput)
                        .keyboardType(.emailAddress).textContentType(.username).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().miloAccountField().focused($focused, equals: .email)
                        .submitLabel(mode == .password ? .next : .go).accessibilityIdentifier("login-email")
                        .onSubmit { if step == .email && mode == .password { focused = .password } else { submit() } }
                    if step == .email && mode == .password { passwordField(reset: false).padding(.top, 14) }
                }
                if !account.statusMessage.isEmpty {
                    Text(account.statusMessage).font(.footnote).foregroundStyle(MiloTheme.dim)
                        .multilineTextAlignment(.center).padding(.top, 14)
                        .accessibilityIdentifier("login-status-message")
                }
                if !account.errorMessage.isEmpty {
                    Text(account.errorMessage).font(.subheadline).foregroundStyle(Color(red: 1, green: 0.65, blue: 0.69))
                        .multilineTextAlignment(.center).lineSpacing(5).padding(.top, 14)
                        .accessibilityIdentifier("login-error-message")
                }
                MiloPrimaryButton(title: submitTitle) { submit() }
                    .disabled(!canSubmit || account.isBusy).padding(.top, 28).accessibilityIdentifier("login-submit")
                if step == .code || step == .reset {
                    SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { _ in
                        let seconds = account.resendSeconds(email: email, purpose: purpose)
                        Button(seconds > 0 ? "\(seconds) 秒后重新发送" : "重新发送验证码") {
                            Task { _ = await account.requestCode(email: email, purpose: purpose) }
                        }.font(.subheadline).foregroundStyle(MiloTheme.hint).frame(minHeight: 44)
                            .disabled(account.isBusy || seconds > 0)
                    }.padding(.top, 10)
                } else if step == .email && mode == .password {
                    Button("忘记密码") { backToEmail(); step = .resetEmail }
                        .font(.subheadline).foregroundStyle(MiloTheme.hint).frame(minHeight: 44).padding(.top, 10)
                        .accessibilityIdentifier("login-forgot-password")
                } else if step == .email {
                    Text("未注册邮箱将自动创建账号").font(.footnote).foregroundStyle(MiloTheme.hint).padding(.top, 18)
                }
            }.frame(maxWidth: 420).padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 32)
                .frame(maxWidth: .infinity).disabled(account.isBusy)
        }.parityScrollMetrics("account-login")
            .scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
            .onAppear(perform: applyFixture)
            .onDisappear { password = ""; newPassword = ""; code = "" }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("page-login")
    }

    private var emailInput: Binding<String> {
        Binding(get: { email }, set: { value in
            guard email != value else { return }
            email = value
            // Clear feedback for user edits, not for the DEBUG fixture's initial state.
            account.clearMessages()
        })
    }

    private var title: String {
        switch step { case .email: "登录 MILO"; case .code: "输入验证码"; case .resetEmail: "找回密码"; case .reset: "设置新密码" }
    }
    private var purpose: VerificationPurpose { step == .reset || step == .resetEmail ? .resetPassword : .signIn }
    private var submitTitle: String {
        if account.isBusy { return step == .reset ? "重置中…" : step == .code || mode == .password ? "登录中…" : "发送中…" }
        if step == .reset { return "重置并登录" }
        if step == .code || (step == .email && mode == .password) || AccountModel.isOwnerEmail(email) { return "登录" }
        return "获取验证码"
    }
    private var canSubmit: Bool {
        switch step {
        case .code: AccountModel.validCode(code)
        case .reset: AccountModel.validCode(code) && AccountModel.validPassword(newPassword)
        case .resetEmail: AccountModel.validEmail(email)
        case .email: AccountModel.isOwnerEmail(email) || (AccountModel.validEmail(email) && (mode == .code || AccountModel.validPassword(password)))
        }
    }
    private var modeSelector: some View {
        HStack(spacing: 8) {
            modeButton("验证码登录", mode: .code)
            modeButton("密码登录", mode: .password)
        }
    }
    private func modeButton(_ title: String, mode next: Mode) -> some View {
        Button(title) { guard mode != next else { return }; mode = next; backToEmail() }
            .font(.subheadline.weight(mode == next ? .medium : .regular))
            .foregroundStyle(mode == next ? MiloTheme.ink : MiloTheme.hint)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(mode == next ? Color.white.opacity(0.09) : .clear, in: Capsule())
            .accessibilityIdentifier(next == .code ? "login-mode-code" : "login-mode-password")
    }
    private func passwordField(reset: Bool) -> some View {
        MiloSecureField(reset ? "新密码（6–32 位）" : "密码",
                        text: feedbackInput(reset ? $newPassword : $password),
                        identifier: reset ? "login-new-password" : "login-password",
                        contentType: reset ? .newPassword : .password)
            .focused($focused, equals: .password).submitLabel(.go).onSubmit(submit)
    }
    private func feedbackInput(_ value: Binding<String>) -> Binding<String> {
        Binding(get: { value.wrappedValue }, set: { next in
            guard value.wrappedValue != next else { return }
            value.wrappedValue = next
            account.clearMessages()
        })
    }
    private func backToEmail() {
        step = .email; password = ""; newPassword = ""; code = ""; account.clearMessages()
    }
    private func submit() {
        guard canSubmit, !account.isBusy else { return }
        focused = nil
        Task {
            let success: Bool
            switch step {
            case .email where AccountModel.isOwnerEmail(email): success = account.signInLocally()
            case .email where mode == .password: success = await account.signIn(email: email, password: password)
            case .email, .resetEmail:
                let isReset = step == .resetEmail
                if await account.requestCode(email: email, purpose: purpose) { step = isReset ? .reset : .code }
                return
            case .code: success = await account.signIn(email: email, code: code)
            case .reset: success = await account.resetPassword(email: email, code: code, password: newPassword)
            }
            if success { password = ""; newPassword = ""; onAuthenticated() }
            else if account.passwordResetRequiresSignIn {
                // The reset code is consumed. Retry password sign-in without
                // accidentally submitting the same reset transaction again.
                step = .email; mode = .password; password = ""; newPassword = ""; code = ""
            }
        }
    }
    private func applyFixture() {
        #if DEBUG
        guard let state = account.fixtureState else { return }
        if state != "email" { email = "milo@example.com" }
        if ["password", "password-error"].contains(state) { mode = .password }
        if ["code", "code-error"].contains(state) { step = .code }
        if state == "reset" { step = .reset }
        #endif
    }
}

extension View {
    func miloAccountField() -> some View {
        self.font(.body).foregroundStyle(MiloTheme.ink).padding(.horizontal, 18).padding(.vertical, 16)
            .frame(minHeight: 54).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 0.7))
            .tint(MiloTheme.accent)
    }
}
