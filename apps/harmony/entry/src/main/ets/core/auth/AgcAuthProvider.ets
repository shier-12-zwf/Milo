import { buffer } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import auth, {
  VerifyCodeAction,
  EmailVerifyCode,
  EmailCredentialInfo,
  VerifyCodeParam,
  SignInParam,
} from '@hw-agconnect/auth';
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
  isValidPassword,
  invalidPasswordError,
  passwordNotSetError,
  wrongPasswordError,
} from './AuthProvider';

/** Name of the AGC config inside entry/src/main/resources/rawfile/. */
const AGC_CONFIG_FILE = 'agconnect-services.json';
/** Locale used for AGC verification-code emails. */
const AGC_LANG = 'zh_CN';
/** Minimum seconds between two code requests enforced client-side. */
const AGC_SEND_INTERVAL = 60;

let agcInitialized = false;

function initAgcOnce(context: common.Context): boolean {
  if (agcInitialized) {
    return true;
  }
  try {
    const raw = context.resourceManager.getRawFileContentSync(AGC_CONFIG_FILE);
    const json = buffer.from(raw.buffer).toString();
    auth.init(context, json);
    agcInitialized = true;
    return true;
  } catch (e) {
    // Missing/broken config must never crash startup; auth calls will fail
    // with typed errors instead.
    console.error('AgcAuthProvider initialization failed');
    return false;
  }
}

/** AGC server code for wrong credentials (code or password). */
const AGC_CODE_BAD_CREDENTIALS = 203818129;
/** AGC server code for wrong email/password pair in password login. */
const AGC_CODE_BAD_LOGIN = 203818032;

/**
 * Translates an error thrown by the AGC auth SDK into the typed AuthError
 * contract. SDK details stay in logs; the login form shows actionable copy.
 */
function mapAgcError(e: Object): AuthError {
  const err = e as BusinessError;
  const code: number = err.code ?? -1;
  const message: string = err.message ?? String(e);
  const normalized = message.toLowerCase();
  console.error(`AgcAuthProvider request failed: ${code}`);
  if (code === AGC_CODE_BAD_LOGIN) {
    return wrongPasswordError();
  }
  if (code === AGC_CODE_BAD_CREDENTIALS) {
    if (normalized.indexOf('password') >= 0) {
      return wrongPasswordError();
    }
    return { reason: 'invalid-code', message: '验证码不正确或已过期，请重试。' };
  }
  if (normalized.indexOf('frequent') >= 0 || normalized.indexOf('too many') >= 0
    || message.indexOf('频繁') >= 0) {
    return { reason: 'rate-limited', message: '操作过于频繁，请稍后再试。' };
  }
  if (normalized.indexOf('network') >= 0 || normalized.indexOf('failed to connect') >= 0
    || normalized.indexOf('timeout') >= 0 || normalized.indexOf('timed out') >= 0) {
    return { reason: 'network', message: '网络连接失败，请检查后重试。' };
  }
  if (normalized.indexOf('password') >= 0 && normalized.indexOf('not set') >= 0) {
    return passwordNotSetError();
  }
  return { reason: 'unknown', message: '暂时无法完成，请稍后重试。' };
}

/** Production auth provider backed by AGC 认证服务 (email + code / password). */
export class AgcAuthProvider implements AuthProvider {
  private context: common.Context;
  private hasPrivacyConsent: () => boolean;

  constructor(context: common.Context, hasPrivacyConsent: () => boolean = () => false) {
    this.context = context;
    this.hasPrivacyConsent = hasPrivacyConsent;
  }

  private prepare(): AuthError | undefined {
    if (!this.hasPrivacyConsent()) {
      return { reason: 'unknown', message: '请先阅读并同意隐私政策和用户协议。' };
    }
    if (!initAgcOnce(this.context)) {
      return { reason: 'unknown', message: '认证服务暂时无法初始化，请稍后重试。' };
    }
    return undefined;
  }

  async sendCode(email: string, purpose: CodePurpose): Promise<SendCodeResult> {
    const consentError = this.prepare();
    if (consentError !== undefined) return { ok: false, error: consentError };
    if (!isValidEmail(email)) {
      const failure: SendCodeResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    const verifyCodeType: EmailVerifyCode = { kind: 'email', email: email.trim() };
    const param: VerifyCodeParam = {
      verifyCodeType: verifyCodeType,
      action: purpose === 'reset-password'
        ? VerifyCodeAction.RESET_PASSWORD
        : VerifyCodeAction.REGISTER_LOGIN,
      lang: AGC_LANG,
      sendInterval: AGC_SEND_INTERVAL,
    };
    try {
      await auth.requestVerifyCode(param);
      return { ok: true };
    } catch (e) {
      const failure: SendCodeResult = { ok: false, error: mapAgcError(e) };
      return failure;
    }
  }

  async signIn(email: string, code: string, password?: string): Promise<SignInResult> {
    const consentError = this.prepare();
    if (consentError !== undefined) return { ok: false, error: consentError };
    if (!isValidEmail(email)) {
      const failure: SignInResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    const credentialInfo: EmailCredentialInfo = {
      kind: 'email',
      email: email.trim(),
      verifyCode: code.trim(),
      password: password !== undefined && password.length > 0 ? password : undefined,
    };
    const param: SignInParam = { credentialInfo: credentialInfo, autoCreateUser: true };
    try {
      const result = await auth.signIn(param);
      const user = result.getUser();
      const session: AuthSession = {
        uid: user.getUid(),
        email: user.getEmail() !== '' ? user.getEmail() : email.trim(),
        provider: 'agc',
      };
      return { ok: true, session: session };
    } catch (e) {
      const failure: SignInResult = { ok: false, error: mapAgcError(e) };
      return failure;
    }
  }

  async signInWithPassword(email: string, password: string): Promise<SignInResult> {
    const consentError = this.prepare();
    if (consentError !== undefined) return { ok: false, error: consentError };
    if (!isValidEmail(email)) {
      const failure: SignInResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    if (!isValidPassword(password)) {
      const failure: SignInResult = { ok: false, error: invalidPasswordError() };
      return failure;
    }
    const credentialInfo: EmailCredentialInfo = {
      kind: 'email',
      email: email.trim(),
      password: password,
    };
    const param: SignInParam = { credentialInfo: credentialInfo };
    try {
      const result = await auth.signIn(param);
      const user = result.getUser();
      const session: AuthSession = {
        uid: user.getUid(),
        email: user.getEmail() !== '' ? user.getEmail() : email.trim(),
        provider: 'agc',
      };
      return { ok: true, session: session };
    } catch (e) {
      const failure: SignInResult = { ok: false, error: mapAgcError(e) };
      return failure;
    }
  }

  async resetPassword(email: string, code: string, newPassword: string): Promise<ResetPasswordResult> {
    const consentError = this.prepare();
    if (consentError !== undefined) return { ok: false, error: consentError };
    if (!isValidEmail(email)) {
      const failure: ResetPasswordResult = { ok: false, error: invalidEmailError() };
      return failure;
    }
    if (!isValidPassword(newPassword)) {
      const failure: ResetPasswordResult = { ok: false, error: invalidPasswordError() };
      return failure;
    }
    const credentialInfo: EmailCredentialInfo = {
      kind: 'email',
      email: email.trim(),
      verifyCode: code.trim(),
      password: newPassword,
    };
    try {
      await auth.resetPassword(credentialInfo);
      return { ok: true };
    } catch (e) {
      const failure: ResetPasswordResult = { ok: false, error: mapAgcError(e) };
      return failure;
    }
  }

  async signOut(): Promise<void> {
    if (this.prepare() !== undefined) return;
    try {
      await auth.signOut();
    } catch (e) {
      // Never block local sign-out on remote cleanup failures.
      console.error(`AgcAuthProvider.signOut: ${String(e)}`);
    }
  }

  async deleteAccount(): Promise<DeleteAccountResult> {
    const consentError = this.prepare();
    if (consentError !== undefined) return { ok: false, error: consentError };
    try {
      const user = await auth.getCurrentUser();
      if (user === null) {
        return { ok: false, error: { reason: 'unknown', message: '请重新登录后注销账号。' } };
      }
      await auth.deleteUser();
      return { ok: true };
    } catch (e) {
      return { ok: false, error: mapAgcError(e) };
    }
  }
}
