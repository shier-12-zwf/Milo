import { buffer } from '@kit.ArkTS';
import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MiloBackNode } from '../ui/MiloButtons';

@Component
export struct LegalDocumentScreen {
  document: string = 'privacy';
  onBack: () => void = () => {};
  @State content: string = '';

  aboutToAppear(): void {
    try {
      const resource = this.document === 'terms' ? 'user-agreement.txt' : 'privacy-policy.txt';
      const raw = this.getUIContext().getHostContext()?.resourceManager.getRawFileContentSync(resource);
      this.content = raw === undefined ? '暂时无法读取文档，请返回后重试。' : buffer.from(raw).toString('utf-8');
    } catch {
      this.content = '暂时无法读取文档，请返回后重试。隐私联系邮箱：1972375139@qq.com';
    }
  }

  build() {
    Column({ space: 16 }) {
      Row() {
        MiloBackNode({ onTap: () => this.onBack() })
        Text(this.document === 'terms' ? '用户协议' : '隐私政策')
          .fontSize(22).fontColor(MILO_COLORS.ink).margin({ left: 16 })
      }.width('100%')
      Scroll() {
        Column({ space: 16 }) {
          Text(this.content).fontSize(15).lineHeight(26).fontColor(MILO_COLORS.inkDim)
            .copyOption(CopyOptions.LocalDevice).width('100%')
          if (this.document !== 'terms') {
            Hyperlink('https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-Guides/agc-auth-harmonyos-arkts-sdksecurity-0000001631246482',
              '查看华为认证服务隐私声明（需联网）')
              .color('#c8bcff').padding({ top: 8, bottom: 8 })
          }
        }.width('100%').padding({ bottom: 24 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
    }.width('100%').height('100%').padding({ left: 24, right: 24, top: 20, bottom: 24 })
  }
}
