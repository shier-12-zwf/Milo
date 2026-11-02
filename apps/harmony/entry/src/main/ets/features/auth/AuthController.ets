import {
  type AuthError,
  type AuthProvider,
  type AuthSession,
  type CodePurpose,
  type ResetPasswordFailure,
  type ResetPasswordResult,
  type SendCodeFailure,
  type SendCodeResult,
  type SignInFailure,
  type SignInResult,
  type SignInSuccess,
  isResetPasswordFailure,
  isSendCodeFailure,
  isSignInFailure,
  invalidPasswordError,
  isValidEmail,
  isValidPassword,
  invalidEmailError,
  isValidVerificationCode,
  invalidCodeError,
} from '../../core/auth/AuthProvider';
import { AuthSessionStore, type DeletionPhase } from '../../core/auth/AuthSessionStore';

/**
 * Owner backdoor: submitting this exact string as the email skips remote auth
 * entirely and signs in a persistent local manager session. It exists so the
 * app owner can never be locked out by the first-launch login gate (e.g. no
 * network on a fresh install). A real address like `milo@x.com` is unaffected.
 */
export const BACKDOOR_EMAIL = 'milo';

export const BACKDOOR_SESSION: AuthSession = {
  uid: 'milo-local-owner',
  email: 'milo',
  provider: 'local',
};

export type AuthPhase =
  | 'checking'
  | 'signedOut'
  | 'sendingCode'
  | 'awaitingCode'
  | 'signingIn'
  | 'signedIn';

export interface AuthControllerDeps {
  provider: AuthProvider;
  store: AuthSessionStore;
  now?: () => number;
}

/**
 * State machine behind the first-launch login gate:
 * checking → signedOut → sendingCode → awaitingCode → signingIn → signedIn.
 * The UI reads phase/error/session after each await; the controller never
 * touches the network for the owner backdoor.
 */
export class AuthController {
  private deps: AuthControllerDeps;
  private phaseValue: AuthPhase = 'checking';
  private errorValue: AuthError | undefined = undefined;
  private sessionValue: AuthSession | undefined = undefined;
  private codeSentAt: number | undefined = undefined;
  private codeSentEmail: string = '';
  private codeSentPurpose: CodePurpose = 'sign-in';
  private deletionPendingSession: AuthSession | undefined = undefined;
  private deletionPhase: DeletionPhase | undefined = undefined;
  private deletionInProgress: boolean = false;

  constructor(deps: AuthControllerDeps) {
    this.deps = deps;
  }

  /** Cold-start hydration from the persisted session. */
  restore(): AuthSession | undefined {
    const recovery = this.deps.store.loadDeletionRecovery();
    this.deletionPendingSession = recovery?.session;
    this.deletionPhase = recovery?.phase;
    const saved = this.deletionPendingSession ?? this.deps.store.load();
    if (saved !== undefined) {
      this.sessionValue = saved;
      this.phaseValue = 'signedIn';
      if (this.deletionPendingSession !== undefined) this.errorValue = this.deletionRecoveryError(saved);
    } else {
      this.sessionValue = undefined;
      this.phaseValue = 'signedOut';
    }
    return saved;
  }

  getPhase(): AuthPhase {
    return this.phaseValue;
  }

  getError(): AuthError | undefined {
    return this.errorValue;
  }

  getSession(): AuthSession | undefined {
    return this.sessionValue;
  }

  /** Pending identities may only be used to retry cleanup, not fresh auth. */
  isDeletionPending(): boolean {
    return this.deletionPendingSession !== undefined;
  }

  isDeletionOutcomeUnknown(): boolean {
    return this.deletionPendingSession !== undefined && this.deletionPhase === 'requested';
  }

  clearError(): void {
    this.errorValue = undefined;
  }

  getResendSeconds(email: string, purpose: CodePurpose = 'sign-in'): number {
    if (this.codeSentAt === undefined || this.codeSentEmail !== email.trim().toLowerCase()
      || this.codeSentPurpose !== purpose) {
      return 0;
    }
    const now = this.deps.now !== undefined ? this.deps.now() : Date.now();
    return Math.max(0, Math.ceil((this.codeSentAt + 60000 - now) / 1000));
  }

  private isBusy(): boolean {
    return this.deletionInProgress || this.phaseValue === 'sendingCode' || this.phaseValue === 'signingIn';
  }

  /** From the code step back to the email step (e.g. wrong address). */
  backToEmail(): void {
    if (!this.isBusy() && this.phaseValue !== 'signedIn') {
      this.phaseValue = 'signedOut';
      this.errorValue = undefined;
      this.pendingEmail = '';
      this.pendingPurpose = 'sign-in';
    }
  }

  /**
   * Submit the email: owner backdoor short-circuits to a local session,
   * otherwise request a verification code from the provider. Resolves with
   * the session when the backdoor signed in, `undefined` otherwise.
   */
  async submitEmail(email: string, purpose: CodePurpose = 'sign-in'): Promise<AuthSession | undefined> {
    if (this.isBusy() || this.phaseValue === 'signedIn') {
      return undefined;
    }
    const trimmed = email.trim();
    if (trimmed.toLowerCase() === BACKDOOR_EMAIL) {
      this.deps.store.save(BACKDOOR_SESSION);
      this.sessionValue = BACKDOOR_SESSION;
      this.errorValue = undefined;
      this.phaseValue = 'signedIn';
      return BACKDOOR_SESSION;
    }
    if (!isValidEmail(trimmed)) {
      this.errorValue = invalidEmailError();
      this.phaseValue = 'signedOut';
      return undefined;
    }
    if (this.getResendSeconds(trimmed, purpose) > 0) {
      // Returning from “change email” should reopen the valid code form
      // without sending another email or leaving the user stuck waiting.
      this.pendingEmail = trimmed;
      this.pendingPurpose = purpose;
      this.errorValue = undefined;
      this.phaseValue = 'awaitingCode';
      return undefined;
    }
    const keepCodeStep = this.phaseValue === 'awaitingCode'
      && this.pendingEmail === trimmed && this.pendingPurpose === purpose;
    this.errorValue = undefined;
    this.phaseValue = 'sendingCode';
    const result: SendCodeResult = await this.deps.provider.sendCode(trimmed, purpose);
    if (isSendCodeFailure(result)) {
      const failure: SendCodeFailure = result as SendCodeFailure;
      this.errorValue = failure.error;
      this.phaseValue = keepCodeStep ? 'awaitingCode' : 'signedOut';
      return undefined;
    }
    this.pendingEmail = trimmed;
    this.pendingPurpose = purpose;
    this.codeSentAt = this.deps.now !== undefined ? this.deps.now() : Date.now();
    this.codeSentEmail = trimmed.toLowerCase();
    this.codeSentPurpose = purpose;
    this.phaseValue = 'awaitingCode';
    return undefined;
  }

  /** Exchange the emailed code for a session; persists it on success. */
  async submitCode(code: string, password?: string): Promise<AuthSession | undefined> {
    if (this.phaseValue !== 'awaitingCode' || this.pendingPurpose !== 'sign-in') {
      return undefined;
    }
    const trimmed = code.trim();
    if (!isValidVerificationCode(trimmed)) {
      this.errorValue = invalidCodeError();
      return undefined;
    }
    if (password !== undefined && password.length > 0 && !isValidPassword(password)) {
      this.errorValue = invalidPasswordError();
      return undefined;
    }
    this.errorValue = undefined;
    this.phaseValue = 'signingIn';
    const email = this.pendingEmail;
    const result: SignInResult = await this.deps.provider.signIn(email, trimmed, password);
    if (isSignInFailure(result)) {
      const failure: SignInFailure = result as SignInFailure;
      this.errorValue = failure.error;
      this.phaseValue = 'awaitingCode';
      return undefined;
    }
    const success: SignInSuccess = result as SignInSuccess;
    const session = success.session;
    this.deps.store.save(session);
    this.sessionValue = session;
    this.phaseValue = 'signedIn';
    return session;
  }

  /**
   * Sign in directly with email + password (returning-user path). The owner
   * backdoor works here too, same as the code flow.
   */
  async submitPassword(email: string, password: string): Promise<AuthSession | undefined> {
    if (this.isBusy() || this.phaseValue === 'signedIn') {
      return undefined;
    }
    const trimmed = email.trim();
    if (trimmed.toLowerCase() === BACKDOOR_EMAIL) {
      this.deps.store.save(BACKDOOR_SESSION);
      this.sessionValue = BACKDOOR_SESSION;
      this.errorValue = undefined;
      this.phaseValue = 'signedIn';
      return BACKDOOR_SESSION;
    }
    if (!isValidEmail(trimmed)) {
      this.errorValue = invalidEmailError();
      this.phaseValue = 'signedOut';
      return undefined;
    }
    if (!isValidPassword(password)) {
      this.errorValue = invalidPasswordError();
      this.phaseValue = 'signedOut';
      return undefined;
    }
    this.errorValue = undefined;
    this.pendingEmail = trimmed;
    this.phaseValue = 'signingIn';
    const result: SignInResult = await this.deps.provider.signInWithPassword(trimmed, password);
    if (isSignInFailure(result)) {
      const failure: SignInFailure = result as SignInFailure;
      this.errorValue = failure.error;
      this.phaseValue = 'signedOut';
      return undefined;
    }
    const success: SignInSuccess = result as SignInSuccess;
    const session = success.session;
    this.deps.store.save(session);
    this.sessionValue = session;
    this.phaseValue = 'signedIn';
    return session;
  }

  /**
   * Complete the forgot-password flow: verify the reset code, set the new
   * password, then immediately sign in with it. Requires a reset code that
   * was requested via `submitEmail(email, 'reset-password')`.
   */
  async submitReset(code: string, newPassword: string): Promise<AuthSession | undefined> {
    if (this.phaseValue !== 'awaitingCode' || this.pendingPurpose !== 'reset-password') {
      return undefined;
    }
    if (!isValidVerificationCode(code)) {
      this.errorValue = invalidCodeError();
      return undefined;
    }
    if (!isValidPassword(newPassword)) {
      this.errorValue = invalidPasswordError();
      return undefined;
    }
    this.errorValue = undefined;
    this.phaseValue = 'signingIn';
    const email = this.pendingEmail;
    const reset: ResetPasswordResult = await this.deps.provider.resetPassword(email, code.trim(), newPassword);
    if (isResetPasswordFailure(reset)) {
      const failure: ResetPasswordFailure = reset as ResetPasswordFailure;
      this.errorValue = failure.error;
      this.phaseValue = 'awaitingCode';
      return undefined;
    }
    const result: SignInResult = await this.deps.provider.signInWithPassword(email, newPassword);
    if (isSignInFailure(result)) {
      const failure: SignInFailure = result as SignInFailure;
      this.errorValue = { reason: failure.error.reason, message: '密码已更新，请用新密码登录。' };
      this.phaseValue = 'signedOut';
      return undefined;
    }
    const success: SignInSuccess = result as SignInSuccess;
    const session = success.session;
    this.deps.store.save(session);
    this.sessionValue = session;
    this.phaseValue = 'signedIn';
    return session;
  }

  /** Forget the session locally and sign out from the remote provider. */
  async signOut(): Promise<void> {
    if (this.isBusy()) return;
    if (this.deletionPendingSession !== undefined) {
      this.errorValue = this.deletionRecoveryError(this.deletionPendingSession);
      return;
    }
    const session = this.sessionValue;
    if (session !== undefined && session.provider !== 'local') {
      await this.deps.provider.signOut();
    }
    this.deps.store.clear();
    this.sessionValue = undefined;
    this.errorValue = undefined;
    this.phaseValue = 'signedOut';
  }

  private pendingEmail: string = '';

  /** Password management keeps the current session, even if the network fails. */
  async sendAccountPasswordCode(): Promise<boolean> {
    const session = this.sessionValue;
    if (session === undefined || session.provider === 'local' || this.isBusy() || this.isDeletionPending()) return false;
    if (this.getResendSeconds(session.email, 'reset-password') > 0) return false;
    this.errorValue = undefined;
    this.phaseValue = 'sendingCode';
    try {
      const result = await this.deps.provider.sendCode(session.email, 'reset-password');
      if (isSendCodeFailure(result)) {
        this.errorValue = (result as SendCodeFailure).error;
        return false;
      }
      this.codeSentAt = this.deps.now !== undefined ? this.deps.now() : Date.now();
      this.codeSentEmail = session.email.trim().toLowerCase();
      this.codeSentPurpose = 'reset-password';
      return true;
    } finally {
      this.phaseValue = 'signedIn';
    }
  }

  async changeAccountPassword(code: string, password: string): Promise<boolean> {
    const session = this.sessionValue;
    if (session === undefined || session.provider === 'local' || this.isBusy() || this.isDeletionPending()) return false;
    if (!isValidVerificationCode(code)) {
      this.errorValue = invalidCodeError();
      return false;
    }
    if (!isValidPassword(password)) {
      this.errorValue = invalidPasswordError();
      return false;
    }
    this.errorValue = undefined;
    this.phaseValue = 'signingIn';
    try {
      const result = await this.deps.provider.resetPassword(session.email, code.trim(), password);
      if (isResetPasswordFailure(result)) {
        this.errorValue = (result as ResetPasswordFailure).error;
        return false;
      }
      return true;
    } finally {
      this.phaseValue = 'signedIn';
    }
  }

  /**
   * Remote deletion is followed by a durable, identity-bound recovery record.
   * The callback must be idempotent and throw if ANY local cleanup fails.
   * The normal session is retained until cleanup succeeds; the recovery record
   * is removed last so even a failed session removal can recover after restart.
   */
  async deleteAccount(cleanupLocalData: () => void): Promise<boolean> {
    const session = this.sessionValue;
    if (session === undefined || this.isBusy()) return false;
    if (this.isDeletionOutcomeUnknown()) {
      this.errorValue = this.deletionRecoveryError(session);
      return false;
    }
    this.deletionInProgress = true;
    this.errorValue = undefined;
    try {
      if (this.deletionPendingSession === undefined) {
        // Fail before remote mutation if the local session store cannot flush.
        this.deps.store.save(session);
        if (session.provider !== 'local') {
          // Persist intent first. If the final marker cannot flush or the
          // process exits, restore must expose UNKNOWN, never normal sign-in
          // or an invented remote-success state.
          this.deps.store.saveDeletionRequested(session);
          this.deletionPendingSession = session;
          this.deletionPhase = 'requested';
          const result = await this.deps.provider.deleteAccount();
          if (!result.ok) {
            this.errorValue = this.deletionRecoveryError(session);
            return false;
          }
        }
        // Keep success in memory before writing so a failed marker flush can
        // be retried in this process without calling deleteUser a second time.
        this.deletionPendingSession = session;
        this.deletionPhase = 'confirmed-deleted';
      }
      this.deps.store.saveDeletionPending(session);
      this.finishLocalDeletion(cleanupLocalData);
      return true;
    } catch (_error) {
      this.errorValue = this.deletionPendingSession !== undefined
        ? this.deletionRecoveryError(session)
        : { reason: 'unknown', message: '注销尚未完成，账号和本机数据仍保留，请重试。' };
      return false;
    } finally {
      this.deletionInProgress = false;
    }
  }

  /** Explicit user-confirmed local erasure; this is NOT remote-success proof. */
  async clearLocalAfterUnknown(cleanupLocalData: () => void): Promise<boolean> {
    const session = this.sessionValue;
    if (session === undefined || this.isBusy() || !this.isDeletionOutcomeUnknown()) return false;
    this.deletionInProgress = true;
    this.errorValue = undefined;
    try {
      this.deps.store.saveDeletionRequested(session);
      if (session.provider !== 'local') await this.deps.provider.signOut();
      this.finishLocalDeletion(cleanupLocalData);
      return true;
    } catch (_error) {
      this.errorValue = this.deletionRecoveryError(session);
      return false;
    } finally {
      this.deletionInProgress = false;
    }
  }

  private finishLocalDeletion(cleanupLocalData: () => void): void {
    cleanupLocalData();
    this.deps.store.clear();
    this.deps.store.clearDeletionPending();
    this.sessionValue = undefined;
    this.deletionPendingSession = undefined;
    this.deletionPhase = undefined;
    this.phaseValue = 'signedOut';
  }

  private deletionRecoveryError(session: AuthSession): AuthError {
    if (this.isDeletionOutcomeUnknown()) {
      return { reason: 'unknown', message: '云端注销结果尚无法确认，本机数据已保留。请联系客服核对；也可另行确认仅清除此设备数据并退出，这不代表云端账号已注销。' };
    }
    return {
      reason: 'unknown',
      message: session.provider === 'local'
        ? '本机账号清理尚未完成，请再次点击注销以继续清理。'
        : '账号已注销，本机数据清理尚未完成，请再次点击注销以继续清理。',
    };
  }
  private pendingPurpose: CodePurpose = 'sign-in';
}
