import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MiloPrimaryButton, MiloBackLink } from '../ui/MiloButtons';
import { LegalDocumentScreen } from './LegalDocumentScreen';

@Component
export struct PrivacyConsentScreen {
  onAccept: () => void = () => {};
  @Prop errorText: string = '';
  @State document: string = '';
  @State declined: boolean = false;

  build() {
    if (this.document.length > 0) {
      LegalDocumentScreen({ document: this.document, onBack: () => { this.document = ''; } })
    } else {
      Scroll() {
        Column({ space: 18 }) {
          Text('欢迎来到 MILO').fontSize(28).fontColor(MILO_COLORS.ink)
          Text('请先了解我们如何保护你的记录')
            .fontSize(17).fontColor('#c8bcff')
          Text('情绪、日记、草稿和头像保存在本机；本版本不提供 AI 生成功能或付费会员。首次登录需要联网使用华为认证服务，处理邮箱、验证码或密码及认证所需信息。')
            .fontSize(15).lineHeight(26).fontColor(MILO_COLORS.inkDim)
          Text('麦克风仅在你使用语音输入时请求。更换头像、保存卡片和导出日记均由你主动操作。你可以在“我的”管理账号、导出记录或注销账号。系统备份及导出的副本由你另行管理。')
            .fontSize(15).lineHeight(26).fontColor(MILO_COLORS.inkDim)
          Text('请阅读以下全文。同意前不会初始化认证服务或发起登录请求。已有记录和登录状态不会因暂不同意而删除。')
            .fontSize(14).lineHeight(24).fontColor(MILO_COLORS.inkDim)
          MiloBackLink({ label: '阅读《隐私政策》', onTap: () => { this.document = 'privacy'; } })
          MiloBackLink({ label: '阅读《用户协议》', onTap: () => { this.document = 'terms'; } })
          if (this.declined) {
            Text('你可以继续阅读协议，或关闭应用。未同意前无法登录或进入日记功能。')
              .fontSize(14).lineHeight(24).fontColor(MILO_COLORS.inkHint)
          }
          if (this.errorText.length > 0) {
            Text(this.errorText).fontSize(14).fontColor('#efb0b0')
          }
          MiloPrimaryButton({ label: '同意隐私政策与用户协议并继续', onTap: () => this.onAccept() })
          MiloBackLink({ label: '暂不同意', onTap: () => { this.declined = true; } })
        }.width('100%').constraintSize({ maxWidth: 480 })
          .padding({ left: 28, right: 28, top: 52, bottom: 32 }).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').scrollBar(BarState.Off)
    }
  }
}
