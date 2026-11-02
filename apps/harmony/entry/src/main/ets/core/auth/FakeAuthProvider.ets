import {
  type AuthProvider,
  type AuthError,
  type AuthSession,
  type CodePurpose,
  type DeleteAccountResult,
  type ResetPasswordResult,
  type SendCodeResult,
  type SignInResult,
  isValidEmail,
  invalidEmailError,
  invalidPasswordError,
  passwordNotSetError,
  wrongPasswordError,
  isValidPassword,
} from './AuthProvider';

/** Fixed code accepted by the fake provider; documented for dev/testing. */
export const FAKE_AUTH_CODE = '000000';

/**
 * In-memory stand-in for the AGC auth service. Powers unit tests without any
 * network or AGC console setup. Implements the full password surface: code
 * login, code+password registration, password login, and reset.
 */
export class FakeAuthProvider implements AuthProvider {
  private sentEmails: string[] = [];
  private sentPurposes: CodePurpose[] = [];
  private passwords: Map<string, string> = new Map();
  private signOutCalls: number = 0;
  deleteCalls: number = 0;
  deleteFails: boolean = false;

  async sendCode(email: string, purpose: CodePurpose): Promise<SendCodeResult> {
    if (!isValidEmail(email)) {
      const failure: SendCodeResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    this.sentEmails.push(email.trim());
    this.sentPurposes.push(purpose);
    return { ok: true };
  }

  async signIn(email: string, code: string, password?: string): Promise<SignInResult> {
    if (!isValidEmail(email)) {
      const failure: SignInResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    if (code.trim() !== FAKE_AUTH_CODE) {
      const error: AuthError = {
        reason: 'invalid-code',
        message: '验证码不对，再检查一下邮件里的数字。',
      };
      const failure: SignInResult = { ok: false, error: error };
      return failure;
    }
    if (password !== undefined && password.length > 0) {
      if (!isValidPassword(password)) {
        const failure: SignInResult = { ok: false, error: invalidPasswordError() };
        return failure;
      }
      this.passwords.set(email.trim(), password);
    }
    const session: AuthSession = {
      uid: `agc-${email.trim()}`,
      email: email.trim(),
      provider: 'agc',
    };
    return { ok: true, session: session };
  }

  async signInWithPassword(email: string, password: string): Promise<SignInResult> {
    if (!isValidEmail(email)) {
      const failure: SignInResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    const stored = this.passwords.get(email.trim());
    if (stored === undefined) {
      const failure: SignInResult = { ok: false, error: passwordNotSetError() };
      return failure;
    }
    if (password !== stored) {
      const failure: SignInResult = { ok: false, error: wrongPasswordError() };
      return failure;
    }
    const session: AuthSession = {
      uid: `agc-${email.trim()}`,
      email: email.trim(),
      provider: 'agc',
    };
    return { ok: true, session: session };
  }

  async resetPassword(email: string, code: string, newPassword: string): Promise<ResetPasswordResult> {
    if (!isValidEmail(email)) {
      const failure: ResetPasswordResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    if (code.trim() !== FAKE_AUTH_CODE) {
      const error: AuthError = {
        reason: 'invalid-code',
        message: '验证码不对，再检查一下邮件里的数字。',
      };
      const failure: ResetPasswordResult = { ok: false, error: error };
      return failure;
    }
    if (!isValidPassword(newPassword)) {
      const failure: ResetPasswordResult = { ok: false, error: invalidPasswordError() };
      return failure;
    }
    this.passwords.set(email.trim(), newPassword);
    return { ok: true };
  }

  async signOut(): Promise<void> {
    this.signOutCalls += 1;
  }

  async deleteAccount(): Promise<DeleteAccountResult> {
    this.deleteCalls += 1;
    if (this.deleteFails) {
      return { ok: false, error: { reason: 'network', message: '网络连接失败，请检查后重试。' } };
    }
    return { ok: true };
  }

  /** Test helpers. */
  codesSentTo(email: string): number {
    let count = 0;
    for (let index = 0; index < this.sentEmails.length; index += 1) {
      if (this.sentEmails[index] === email) {
        count += 1;
      }
    }
    return count;
  }

  lastPurpose(): CodePurpose | undefined {
    return this.sentPurposes.length > 0
      ? this.sentPurposes[this.sentPurposes.length - 1]
      : undefined;
  }

  passwordFor(email: string): string | undefined {
    return this.passwords.get(email.trim());
  }

  signOutCallCount(): number {
    return this.signOutCalls;
  }
}
