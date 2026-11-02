import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MiloPrimaryButton, MiloBackNode } from '../ui/MiloButtons';
import { Haptics } from '../../core/system/Haptics';
import {
  isValidEmail,
  isValidPassword,
  isValidVerificationCode,
  type AuthSession,
  type CodePurpose,
} from '../../core/auth/AuthProvider';
import { AuthController, BACKDOOR_EMAIL } from './AuthController';
import { LegalDocumentScreen } from '../legal/LegalDocumentScreen';

/** Email-code sign-in auto-creates new accounts; returning users can use a password. */
@Component
export struct LoginScreen {
  controller: AuthController | null = null;
  onSignedIn: (session: AuthSession) => void = () => {};
  @State mode: 'code' | 'password' = 'code';
  @State step: 'email' | 'code' | 'resetEmail' | 'reset' = 'email';
  @State email: string = '';
  @State code: string = '';
  @State password: string = '';
  @State newPassword: string = '';
  @State error: string = '';
  @State busy: boolean = false;
  @State resendSeconds: number = 0;
  @State legalDocument: string = '';
  private cooldownTimer: number = -1;
  private haptics: Haptics = new Haptics();

  aboutToAppear(): void {
    this.cooldownTimer = setInterval(() => this.syncCooldown(), 1000);
  }

  aboutToDisappear(): void {
    if (this.cooldownTimer >= 0) {
      clearInterval(this.cooldownTimer);
      this.cooldownTimer = -1;
    }
  }

  private isBackdoor(): boolean {
    return this.email.trim().toLowerCase() === BACKDOOR_EMAIL;
  }

  private canSubmitEmail(): boolean {
    return this.isBackdoor() || isValidEmail(this.email);
  }

  private canSubmitPassword(): boolean {
    return this.isBackdoor() || (isValidEmail(this.email) && isValidPassword(this.password));
  }

  private codePurpose(): CodePurpose {
    return this.step === 'reset' || this.step === 'resetEmail' ? 'reset-password' : 'sign-in';
  }

  private syncCooldown(): void {
    this.resendSeconds = this.controller?.getResendSeconds(this.email, this.codePurpose()) ?? 0;
  }

  private syncError(): void {
    this.error = this.controller?.getError()?.message ?? '';
  }

  private clearError(): void {
    this.error = '';
    this.controller?.clearError();
  }

  private switchMode(mode: 'code' | 'password'): void {
    if (this.busy || this.mode === mode) {
      return;
    }
    this.mode = mode;
    this.backToEmail();
  }

  private async submitEmail(): Promise<void> {
    if (this.busy || this.controller === null || !this.canSubmitEmail()) {
      return;
    }
    const purpose = this.codePurpose();
    this.busy = true;
    this.clearError();
    const session = await this.controller.submitEmail(this.email, purpose);
    this.busy = false;
    this.syncError();
    this.syncCooldown();
    if (session !== undefined) {
      this.onSignedIn(session);
      return;
    }
    if (this.controller.getPhase() === 'awaitingCode') {
      this.haptics.selection();
      this.step = purpose === 'reset-password' ? 'reset' : 'code';
    }
  }

  private async submitCode(): Promise<void> {
    if (this.busy || this.controller === null || !isValidVerificationCode(this.code)) {
      return;
    }
    this.busy = true;
    this.clearError();
    const session = await this.controller.submitCode(this.code);
    this.busy = false;
    this.syncError();
    if (session !== undefined) {
      this.onSignedIn(session);
    }
  }

  private async submitPassword(): Promise<void> {
    if (this.busy || this.controller === null || !this.canSubmitPassword()) {
      return;
    }
    this.busy = true;
    this.clearError();
    const session = await this.controller.submitPassword(this.email, this.password);
    this.busy = false;
    this.syncError();
    if (session !== undefined) {
      this.onSignedIn(session);
    }
  }

  private startReset(): void {
    if (this.busy) {
      return;
    }
    this.backToEmail();
    this.step = 'resetEmail';
    this.syncCooldown();
  }

  private async submitReset(): Promise<void> {
    if (this.busy || this.controller === null
      || !isValidVerificationCode(this.code) || !isValidPassword(this.newPassword)) {
      return;
    }
    this.busy = true;
    this.clearError();
    const session = await this.controller.submitReset(this.code, this.newPassword);
    this.busy = false;
    this.syncError();
    if (session !== undefined) {
      this.onSignedIn(session);
    } else if (this.controller.getPhase() === 'signedOut') {
      // The reset succeeded but the follow-up login failed. Do not reuse
      // the consumed reset code: return to a working password login form.
      this.mode = 'password';
      this.step = 'email';
      this.password = this.newPassword;
      this.newPassword = '';
      this.code = '';
    }
  }

  private backToEmail(): void {
    if (this.busy) {
      return;
    }
    this.step = 'email';
    this.code = '';
    this.password = '';
    this.newPassword = '';
    this.clearError();
    this.controller?.backToEmail();
    this.syncCooldown();
  }

  private submitLabel(): string {
    if (this.busy) {
      return this.step === 'reset' ? '重置中…' : this.step === 'code'
        || (this.step === 'email' && this.mode === 'password') ? '登录中…' : '发送中…';
    }
    if (this.step === 'reset') {
      return '重置并登录';
    }
    if (this.step === 'code' || (this.step === 'email' && this.mode === 'password') || this.isBackdoor()) {
      return '登录';
    }
    return this.resendSeconds > 0 ? '输入验证码' : '获取验证码';
  }

  private canSubmit(): boolean {
    if (this.busy) {
      return false;
    }
    if (this.step === 'reset') {
      return isValidVerificationCode(this.code) && isValidPassword(this.newPassword);
    }
    if (this.step === 'code') {
      return isValidVerificationCode(this.code);
    }
    return this.step === 'email' && this.mode === 'password'
      ? this.canSubmitPassword() : this.canSubmitEmail();
  }

  private submit(): void {
    if (this.step === 'reset') {
      void this.submitReset();
    } else if (this.step === 'code') {
      void this.submitCode();
    } else if (this.step === 'email' && this.mode === 'password') {
      void this.submitPassword();
    } else {
      void this.submitEmail();
    }
  }

  @Builder
  modeToggle() {
    Row({ space: 8 }) {
      Button('验证码登录')
        .fontSize(15)
        .fontColor(this.mode === 'code' ? MILO_COLORS.ink : MILO_COLORS.inkHint)
        .fontWeight(this.mode === 'code' ? FontWeight.Medium : FontWeight.Normal)
        .backgroundColor(this.mode === 'code' ? 'rgba(255,255,255,0.09)' : Color.Transparent)
        .layoutWeight(1)
        .height(44)
        .enabled(!this.busy)
        .onClick(() => this.switchMode('code'))
      Button('密码登录')
        .fontSize(15)
        .fontColor(this.mode === 'password' ? MILO_COLORS.ink : MILO_COLORS.inkHint)
        .fontWeight(this.mode === 'password' ? FontWeight.Medium : FontWeight.Normal)
        .backgroundColor(this.mode === 'password' ? 'rgba(255,255,255,0.09)' : Color.Transparent)
        .layoutWeight(1)
        .height(44)
        .enabled(!this.busy)
        .onClick(() => this.switchMode('password'))
    }
    .width('100%')
    .margin({ bottom: 24 })
  }

  @Builder
  emailField() {
    TextInput({ placeholder: '邮箱地址', text: this.email })
      .onChange((value: string) => {
        this.email = value;
        this.clearError();
        this.syncCooldown();
      })
      .type(InputType.Email)
      .enterKeyType(this.step === 'email' && this.mode === 'password' ? EnterKeyType.Next : EnterKeyType.Done)
      .onSubmit(() => {
        if (this.step === 'email' && this.mode === 'password') {
          this.getUIContext().getFocusController().requestFocus('auth-password');
        } else {
          this.submit();
        }
      })
      .enabled(!this.busy)
      .width('100%')
      .height(54)
      .padding({ left: 18, right: 18 })
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.05)')
      .border({ width: 1, color: 'rgba(255,255,255,0.12)' })
      .fontColor(MILO_COLORS.ink)
      .fontSize(16)
      .placeholderColor(MILO_COLORS.inkHint)
      .placeholderFont({ size: 15 })
  }

  @Builder
  codeField() {
    TextInput({ placeholder: '6 位验证码', text: this.code })
      .onChange((value: string) => {
        this.code = value;
        this.clearError();
      })
      .type(InputType.Number)
      .maxLength(6)
      .enterKeyType(this.step === 'reset' ? EnterKeyType.Next : EnterKeyType.Done)
      .onSubmit(() => {
        if (this.step === 'reset') {
          this.getUIContext().getFocusController().requestFocus('auth-password');
        } else {
          this.submit();
        }
      })
      .enabled(!this.busy)
      .width('100%')
      .height(58)
      .padding({ left: 18, right: 18 })
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.05)')
      .border({ width: 1, color: 'rgba(255,255,255,0.12)' })
      .fontColor(MILO_COLORS.ink)
      .fontSize(22)
      .textAlign(TextAlign.Center)
      .placeholderColor(MILO_COLORS.inkHint)
      .placeholderFont({ size: 15 })
  }

  @Builder
  passwordField() {
    TextInput({
      placeholder: this.step === 'reset' ? '新密码（6–32 位）' : '密码',
      text: this.step === 'reset' ? this.newPassword : this.password,
    })
      .id('auth-password')
      .onChange((value: string) => {
        if (this.step === 'reset') {
          this.newPassword = value;
        } else {
          this.password = value;
        }
        this.clearError();
      })
      .type(InputType.Password)
      .enterKeyType(EnterKeyType.Done)
      .onSubmit(() => this.submit())
      .enabled(!this.busy)
      .width('100%')
      .height(54)
      .padding({ left: 18, right: 18 })
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.05)')
      .border({ width: 1, color: 'rgba(255,255,255,0.12)' })
      .fontColor(MILO_COLORS.ink)
      .fontSize(16)
      .placeholderColor(MILO_COLORS.inkHint)
      .placeholderFont({ size: 15 })
      .showPasswordIcon(true)
      .margin({ top: 14 })
  }

  build() {
    if (this.legalDocument.length > 0) {
      LegalDocumentScreen({ document: this.legalDocument, onBack: () => { this.legalDocument = ''; } })
    } else {
    Scroll() {
      Column() {
        Row() {
          if (this.step !== 'email') {
            MiloBackNode({ onTap: () => this.backToEmail() })
              .enabled(!this.busy)
          }
        }
        .width('100%')
        .height(44)

        Text('MILO')
          .fontSize(36)
          .fontFamily('serif')
          .fontWeight(FontWeight.Medium)
          .fontColor(MILO_COLORS.ink)
          .letterSpacing(6)
          .margin({ top: 32, bottom: 36 })

        Text(this.step === 'resetEmail' ? '找回密码' : this.step === 'reset'
          ? '设置新密码' : this.step === 'code' ? '输入验证码' : '登录 MILO')
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor(MILO_COLORS.ink)
          .margin({ bottom: 24 })

        if (this.step === 'email') {
          this.modeToggle()
        }

        if (this.step === 'code' || this.step === 'reset') {
          Text(`已发送至 ${this.email.trim()}`)
            .fontSize(14)
            .lineHeight(22)
            .fontColor(MILO_COLORS.inkHint)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ bottom: 24 })
          this.codeField()
          if (this.step === 'reset') {
            this.passwordField()
          }
        } else {
          this.emailField()
          if (this.step === 'email' && this.mode === 'password') {
            this.passwordField()
          }
        }

        if (this.error.length > 0) {
          Text(this.error)
            .fontSize(14)
            .lineHeight(22)
            .fontColor('rgba(255,164,173,0.92)')
            .margin({ top: 14 })
            .width('100%')
            .textAlign(TextAlign.Center)
        }

        MiloPrimaryButton({
          label: this.submitLabel(),
          active: this.canSubmit(),
          onTap: () => this.submit(),
        })
          .margin({ top: 28 })

        if (this.step === 'code' || this.step === 'reset') {
          Button(this.resendSeconds > 0 ? `${this.resendSeconds} 秒后重新发送` : '重新发送验证码')
            .backgroundColor(Color.Transparent)
            .fontColor(MILO_COLORS.inkHint)
            .fontSize(14)
            .height(44)
            .enabled(!this.busy && this.resendSeconds === 0)
            .margin({ top: 10 })
            .onClick(() => {
              void this.submitEmail();
            })
        } else if (this.step === 'email' && this.mode === 'password') {
          Button('忘记密码')
            .backgroundColor(Color.Transparent)
            .fontColor(MILO_COLORS.inkHint)
            .fontSize(14)
            .height(44)
            .enabled(!this.busy)
            .margin({ top: 10 })
            .onClick(() => this.startReset())
        } else if (this.step === 'email') {
          Text('未注册邮箱将自动创建账号')
            .fontSize(13)
            .fontColor(MILO_COLORS.inkHint)
            .margin({ top: 18 })
        }
        Row({ space: 12 }) {
          Button('隐私政策').backgroundColor(Color.Transparent).fontColor('#c8bcff').fontSize(14)
            .onClick(() => { this.legalDocument = 'privacy'; })
          Button('用户协议').backgroundColor(Color.Transparent).fontColor('#c8bcff').fontSize(14)
            .onClick(() => { this.legalDocument = 'terms'; })
        }.margin({ top: 20 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 420 })
      .padding({ left: 28, right: 28, top: 20, bottom: 32 })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    }
  }
}
