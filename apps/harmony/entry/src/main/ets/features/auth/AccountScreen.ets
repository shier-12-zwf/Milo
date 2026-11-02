import { AuthController } from './AuthController';
import { MiloBackNode, MiloPrimaryButton, MiloBackLink } from '../ui/MiloButtons';
import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MoodPlanet } from '../mood/MoodPlanet';
import { PersonalFiles } from '../../core/system/PersonalFiles';
import { DiaryEntry } from '../../core/model/Domain';
import { ApiKeyStore } from '../../core/auth/ApiKeyStore';
import { UserAiSettingsRepository } from '../../core/config/UserAiSettings';
import { APP_FILING_NUMBER, MIIT_FILING_URL } from '../../core/config/ComplianceConfig';
import { AI_AVAILABLE } from '../../core/config/FeatureFlags';
import { LegalDocumentScreen } from '../legal/LegalDocumentScreen';

@Component
export struct AccountScreen {
  controller: AuthController | null = null;
  onBack: () => void = () => {};
  onSignOut: () => void = () => {};
  onDeleted: () => void = () => {};
  onClearLocalData: () => void = () => {};
  onAiSettings: () => void = () => {};
  files: PersonalFiles | null = null;
  keyStore: ApiKeyStore | null = null;
  aiRepository: UserAiSettingsRepository | null = null;
  @Prop entries: DiaryEntry[] = [];
  @State avatarPath: string = '';
  @State busy: boolean = false;
  @State errorText: string = '';
  @Prop entryCount: number = 0;
  @State passwordOpen: boolean = false;
  @State code: string = '';
  @State password: string = '';
  @State confirmation: string = '';
  @State notice: string = '';
  @State cooldown: number = 0;
  @State legalDocument: string = '';
  @State deletionPending: boolean = false;
  @State deletionOutcomeUnknown: boolean = false;
  private timer: number = -1;

  aboutToAppear(): void {
    this.avatarPath = this.files?.avatar() ?? '';
    this.deletionPending = this.controller?.isDeletionPending() ?? false;
    this.deletionOutcomeUnknown = this.controller?.isDeletionOutcomeUnknown() ?? false;
    this.updateCooldown();
    this.timer = setInterval(() => this.updateCooldown(), 1000);
  }

  private async pickAvatar(): Promise<void> {
    if (this.busy || this.files === null) return;
    this.busy = true;
    this.errorText = '';
    try { this.avatarPath = await this.files.chooseAvatar(); }
    catch { this.errorText = '头像未更新，请选择可读取且小于 20 MB 的图片。'; }
    finally { this.busy = false; }
  }

  private async exportDiaries(format: string): Promise<void> {
    if (this.busy || this.files === null) return;
    this.busy = true;
    this.errorText = '';
    this.notice = '';
    try {
      const saved = await this.files.export(this.entries, format);
      this.notice = saved ? `已导出 ${this.entries.length} 篇日记到所选位置。` : '已取消导出。';
    } catch { this.errorText = '导出失败，请检查存储空间并重试；原日记已保留。'; }
    finally { this.busy = false; }
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) clearInterval(this.timer);
    this.password = '';
    this.confirmation = '';
    this.code = '';
  }

  private updateCooldown(): void {
    this.cooldown = this.controller?.getResendSeconds(this.controller?.getSession()?.email ?? '', 'reset-password') ?? 0;
  }

  private async sendCode(): Promise<void> {
    if (this.busy || this.controller === null || this.cooldown > 0) return;
    this.busy = true;
    this.errorText = '';
    this.notice = '';
    try {
      if (await this.controller.sendAccountPasswordCode()) this.notice = '验证码已发送到绑定邮箱。';
      else this.errorText = this.controller.getError()?.message ?? '请稍后再试。';
      this.updateCooldown();
    } catch (e) {
      this.errorText = '发送失败，请检查网络后重试。';
    } finally {
      this.busy = false;
    }
  }

  private async changePassword(): Promise<void> {
    if (this.busy || this.controller === null) return;
    this.errorText = '';
    this.notice = '';
    if (this.password !== this.confirmation) {
      this.errorText = '两次输入的密码不一致。';
      return;
    }
    this.busy = true;
    try {
      if (await this.controller.changeAccountPassword(this.code, this.password)) {
        this.password = '';
        this.confirmation = '';
        this.code = '';
        this.passwordOpen = false;
        this.notice = '密码已更新，下次请使用新密码登录。';
      } else this.errorText = this.controller.getError()?.message ?? '暂时无法修改，请重试。';
    } catch (e) {
      this.errorText = '修改失败，请检查网络后重试。';
    } finally {
      this.busy = false;
    }
  }

  @Builder
  infoRow(title: string, value: string) {
    Row({ space: 12 }) {
      Text(title).fontSize(14).fontColor(MILO_COLORS.inkDim)
      Blank()
      Text(value).fontSize(14).fontColor(MILO_COLORS.ink)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: '65%' })
    }.width('100%').height(48)
  }

  private async removeAccount(): Promise<void> {
    if (this.busy || this.controller === null) return;
    this.busy = true;
    this.errorText = '';
    try {
      if (await this.controller.deleteAccount(() => this.clearCurrentLocalData())) {
        this.onDeleted();
      } else {
        this.errorText = this.controller.getError()?.message ?? '暂时无法注销，请重试。';
      }
    } catch (e) {
      this.errorText = '暂时无法注销，请重试。';
    } finally {
      this.deletionPending = this.controller?.isDeletionPending() ?? false;
      this.deletionOutcomeUnknown = this.controller?.isDeletionOutcomeUnknown() ?? false;
      this.busy = false;
    }
  }

  private clearCurrentLocalData(): void {
    this.files?.resetAvatar();
    this.aiRepository?.clear();
    this.keyStore?.clear();
    this.onClearLocalData();
  }

  private confirmUnknownLocalCleanup(): void {
    if (this.busy || !this.deletionOutcomeUnknown) return;
    this.getUIContext().showAlertDialog({
      title: '仅清理本机数据并退出？',
      message: '云端注销结果尚无法确认。此操作只删除此设备的日记、草稿、头像设置和登录状态，无法恢复，不代表云端账号已注销。请先导出需要的记录；已导出文件及图库图片仍会保留。如需确认云端账号状态，请联系 1972375139@qq.com。',
      primaryButton: { value: '取消，保留本机记录', action: () => {} },
      secondaryButton: { value: '确认清理本机并退出', action: () => { void this.clearLocalAfterUnknown(); } },
    });
  }

  private async clearLocalAfterUnknown(): Promise<void> {
    if (this.busy || this.controller === null || !this.deletionOutcomeUnknown) return;
    this.busy = true;
    this.errorText = '';
    try {
      if (await this.controller.clearLocalAfterUnknown(() => this.clearCurrentLocalData())) {
        const uiContext = this.getUIContext();
        this.onDeleted();
        uiContext.showAlertDialog({
          title: '本机数据已清理',
          message: '这不代表云端账号已注销。如需确认云端账号状态，请联系 1972375139@qq.com。',
          primaryButton: { value: '知道了', action: () => {} },
        });
      } else {
        this.errorText = this.controller.getError()?.message ?? '本机清理尚未完成，请重试。';
      }
    } catch {
      this.errorText = '本机清理尚未完成，请重试。云端注销结果仍需另行确认。';
    } finally {
      this.deletionPending = this.controller?.isDeletionPending() ?? false;
      this.deletionOutcomeUnknown = this.controller?.isDeletionOutcomeUnknown() ?? false;
      this.busy = false;
    }
  }

  build() {
    if (this.legalDocument.length > 0) {
      LegalDocumentScreen({ document: this.legalDocument, onBack: () => { this.legalDocument = ''; } })
    } else {
    Column({ space: 16 }) {
      Row() {
        MiloBackNode({ onTap: () => this.onBack() }).enabled(!this.deletionPending)
        Text('我的').fontSize(22).fontColor(MILO_COLORS.ink).margin({ left: 16 })
      }.width('100%')
      Scroll() {
        Column({ space: 20 }) {
          if (this.deletionPending) {
            if (this.deletionOutcomeUnknown) {
              Text('云端注销结果尚无法确认，请核对。本机记录不会自动删除，你仍可先导出记录，再选择仅清理本机数据并退出。这不代表云端账号已注销，如需确认请联系 1972375139@qq.com。')
                .fontSize(14).lineHeight(24).fontColor('#efc38e')
              MiloPrimaryButton({ label: '选择清理本机数据并退出', active: !this.busy,
                onTap: () => this.confirmUnknownLocalCleanup() })
            } else {
              Text(this.controller?.getSession()?.provider === 'local'
                ? '本机数据尚未清理完成。请点击下方“重试清理本机数据”。'
                : '云端账号已注销，本机数据尚未清理完成。请点击下方“重试清理本机数据”，完成前不要退出登录或重新注册。')
                .fontSize(14).lineHeight(24).fontColor('#efc38e')
              MiloPrimaryButton({ label: '重试清理本机数据', active: !this.busy,
                onTap: () => { void this.removeAccount(); } })
            }
          }
          Column({ space: 10 }) {
            Stack() {
              if (this.avatarPath.length > 0) {
                Image(`file://${this.avatarPath}`).width(80).height(80).objectFit(ImageFit.Cover).borderRadius(40)
                  .onError(() => { this.avatarPath = ''; })
              } else {
                MoodPlanet({ moodId: 'okay', planetSize: 84 })
              }
            }.width(84).height(84).onClick(() => { void this.pickAvatar(); }).enabled(!this.busy)
            MiloBackLink({ label: '更换头像', onTap: () => { void this.pickAvatar(); } }).enabled(!this.busy)
            if (this.avatarPath.length > 0) {
              MiloBackLink({ label: '恢复星球头像', onTap: () => {
                this.files?.resetAvatar(); this.avatarPath = '';
              } }).enabled(!this.busy)
            }
            Text(this.controller?.getSession()?.email ?? 'MILO 用户')
              .fontSize(17).fontColor(MILO_COLORS.ink).maxLines(2)
            Text(`已收藏 ${this.entryCount} 段回忆`).fontSize(13).fontColor(MILO_COLORS.inkHint)
          }.width('100%').padding({ top: 16, bottom: 8 })

          Column() {
            Text('账号与安全').fontSize(13).fontColor('#b9aefc').margin({ bottom: 8 })
            this.infoRow('登录方式', this.controller?.getSession()?.provider === 'local' ? '本地体验账号' : '邮箱登录')
            this.infoRow('绑定邮箱', this.controller?.getSession()?.provider === 'local' ? '未绑定' : (this.controller?.getSession()?.email ?? ''))
            if (this.controller?.getSession()?.provider !== 'local') {
              Row() {
                Text('修改密码').fontSize(15).fontColor(MILO_COLORS.ink)
                Blank()
                Text(this.passwordOpen ? '收起  ⌃' : '邮箱验证  ›').fontSize(13).fontColor(MILO_COLORS.inkHint)
              }.width('100%').height(48).onClick(() => {
                if (!this.busy) {
                  this.passwordOpen = !this.passwordOpen;
                  this.password = '';
                  this.confirmation = '';
                  this.code = '';
                  this.errorText = '';
                }
              })
            } else {
              Text('本地体验账号无需密码。使用邮箱账号登录后可管理密码。')
                .fontSize(12).fontColor(MILO_COLORS.inkHint).lineHeight(20)
            }
            if (this.passwordOpen) {
              Column({ space: 12 }) {
                TextInput({ placeholder: '邮箱验证码', text: this.code })
                  .type(InputType.Number).maxLength(6).fontColor(MILO_COLORS.ink)
                  .backgroundColor('rgba(255,255,255,0.07)').onChange((value: string) => { this.code = value; })
                MiloBackLink({ label: this.cooldown > 0 ? `${this.cooldown} 秒后重发` : '发送验证码', onTap: () => { void this.sendCode(); } })
                  .enabled(!this.busy && this.cooldown === 0)
                TextInput({ placeholder: '新密码', text: this.password })
                  .type(InputType.Password).maxLength(32).fontColor(MILO_COLORS.ink)
                  .backgroundColor('rgba(255,255,255,0.07)').onChange((value: string) => { this.password = value; })
                TextInput({ placeholder: '再次输入新密码', text: this.confirmation })
                  .type(InputType.Password).maxLength(32).fontColor(MILO_COLORS.ink)
                  .backgroundColor('rgba(255,255,255,0.07)').onChange((value: string) => { this.confirmation = value; })
                Text('密码为 6–32 位，首尾不留空格。').fontSize(12).fontColor(MILO_COLORS.inkHint)
                MiloPrimaryButton({ label: this.busy ? '请稍候…' : '保存新密码', active: !this.busy, onTap: () => { void this.changePassword(); } })
              }.padding({ top: 12 })
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(18).borderRadius(16)
            .backgroundColor('rgba(255,255,255,0.05)')

          if (AI_AVAILABLE) {
            Column({ space: 10 }) {
              Text('AI 与会员').fontSize(13).fontColor('#b9aefc')
              Text('连接自己的大模型，或了解 MILO 星球会员。').fontSize(13).fontColor(MILO_COLORS.inkDim)
              MiloBackLink({ label: 'AI 设置与月订阅方案  ›', onTap: () => this.onAiSettings() }).enabled(!this.busy)
            }.width('100%').alignItems(HorizontalAlign.Start).padding(18).borderRadius(16)
              .backgroundColor('rgba(255,255,255,0.05)')
          }

          Column({ space: 10 }) {
            Text('回忆与数据').fontSize(13).fontColor('#b9aefc')
            Text('导出全部情绪、日记与对话，保存在你选择的本地文件夹。导出内容不含账号密码或 API Key。')
              .fontSize(13).lineHeight(22).fontColor(MILO_COLORS.inkDim)
            MiloBackLink({ label: '导出 Markdown（方便阅读）', onTap: () => { void this.exportDiaries('md'); } }).enabled(!this.busy)
            MiloBackLink({ label: '导出 JSON（完整数据）', onTap: () => { void this.exportDiaries('json'); } }).enabled(!this.busy)
            Text('日记和草稿保存在当前设备，暂不支持账号间同步。退出登录不会删除本机回忆。')
              .fontSize(13).lineHeight(22).fontColor(MILO_COLORS.inkDim)
            Text('注销账号会同时删除本机日记与草稿，请提前保存想留下的回忆卡片。')
              .fontSize(13).lineHeight(22).fontColor(MILO_COLORS.inkDim)
          }.width('100%').alignItems(HorizontalAlign.Start).padding(18).borderRadius(16)
            .backgroundColor('rgba(255,255,255,0.05)')

          Column({ space: 10 }) {
            Text('关于 MILO').fontSize(13).fontColor('#b9aefc')
            Text('MILO 米洛 · 留住每一份感受').fontSize(13).fontColor(MILO_COLORS.inkDim)
            MiloBackLink({ label: '隐私政策  ›', onTap: () => { this.legalDocument = 'privacy'; } })
            MiloBackLink({ label: '用户协议  ›', onTap: () => { this.legalDocument = 'terms'; } })
            if (APP_FILING_NUMBER.length > 0) {
              Text('APP 备案号').fontSize(12).fontColor(MILO_COLORS.inkHint)
              Hyperlink(MIIT_FILING_URL, APP_FILING_NUMBER)
                .color('#c8bcff').padding({ top: 6, bottom: 6 })
                .accessibilityText(`APP 备案号 ${APP_FILING_NUMBER}，查看工信部备案信息`)
            }
          }.width('100%').alignItems(HorizontalAlign.Start).padding(18).borderRadius(16)
            .backgroundColor('rgba(255,255,255,0.05)')
        }.width('100%').padding({ bottom: 12 })
      }.layoutWeight(1).scrollBar(BarState.Off).width('100%')
      if (this.notice.length > 0) {
        Text(this.notice).fontSize(13).fontColor('#b9dfce')
      }
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(14).fontColor('#efb0b0')
      }
      MiloPrimaryButton({ label: '退出登录', onTap: () => {
        this.getUIContext().showAlertDialog({
          title: '退出登录？', message: '本机回忆会保留，再次使用时需要登录。',
          primaryButton: { value: '取消', action: () => {} },
          secondaryButton: { value: '退出登录', action: () => this.onSignOut() },
        });
      } })
        .enabled(!this.busy && !this.deletionPending)
      MiloBackLink({
        label: '注销账号',
        onTap: () => {
          if (this.busy) return;
          this.getUIContext().showAlertDialog({
            title: '注销账号？',
            message: '将注销 MILO 账号，并删除此设备的日记和草稿，无法恢复。已保存到相册的图片不会删除。',
            primaryButton: { value: '取消', action: () => {} },
            secondaryButton: { value: '注销并删除', action: () => { void this.removeAccount(); } },
          });
        },
      })
        .enabled(!this.busy && !this.deletionPending)
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 20, bottom: 32 })
    }
  }
}
