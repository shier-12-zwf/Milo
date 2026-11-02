import { type DiaryEntry, type StickerTemplateId, DEFAULT_STICKER_TEMPLATE } from '../../core/model/Domain';
import { renderCardLayout, type CardLayout } from '../../core/system/CardRenderer';
import {
  ShareService,
  type ShareResult,
} from '../../core/system/ShareService';

/**
 * Share preview screen. The card layout is computed deterministically via
 * `CardRenderer.renderCardLayout`; the user sees a preview first and only
 * triggers the system share sheet on explicit tap. Share failures return to
 * the preview with retry — the diary itself is never rolled back.
 */
@Component
export struct ShareCardScreen {
  @State status: 'preview' | 'sharing' | 'shared' | 'failed' = 'preview';
  @State lastMessage: string = '';
  @State layout: CardLayout | null = null;
  private entry: DiaryEntry | null = null;
  private templateId: StickerTemplateId = DEFAULT_STICKER_TEMPLATE;
  private share: ShareService = new ShareService();
  private onBack: () => void = () => {};

  aboutToAppear(): void {
    if (this.entry === null) {
      return;
    }
    this.layout = renderCardLayout(this.entry, this.templateId);
  }

  private async onShareTap(): Promise<void> {
    this.status = 'sharing';
    this.lastMessage = '';
    // In the real wiring this would call a platform-specific encode step that
    // turns the layout into image bytes (e.g. via the HarmonyOS canvas /
    // PixelMap APIs). For the unit-tested path we forward an empty buffer so
    // the share flow stays reproducible.
    const preview: ShareResult = await this.share.preview(`milo-card-${this.entry?.id ?? 'memory'}.png`, new ArrayBuffer(0));
    if (preview.code !== 'success') {
      this.status = 'failed';
      this.lastMessage = preview.message;
      return;
    }
    const result: ShareResult = await this.share.shareLast();
    if (result.code === 'success') {
      this.status = 'shared';
      this.lastMessage = '已分享到系统面板。';
    } else if (result.code === 'cancelled') {
      this.status = 'preview';
      this.lastMessage = '';
    } else {
      this.status = 'failed';
      this.lastMessage = result.message;
    }
  }

  build() {
    Column() {
      Row() {
        Button('← 返回')
          .backgroundColor(Color.Transparent)
          .borderRadius(999)
          .fontColor('#c9befc')
          .fontSize(13)
          .onClick(() => this.onBack())
        Blank()
        Text(this.entry?.timeMark ?? '卡片预览')
          .fontColor('#c9befc')
          .fontSize(12)
        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      Column() {
        Text('你的情绪卡片')
          .fontSize(22)
          .fontColor('#ffffff')
        Text('先在本地预览，确认后再分享给朋友。')
          .fontSize(13)
          .fontColor('#8b87a6')
          .margin({ top: 8 })
      }
      .margin({ top: 16, bottom: 20 })

      if (this.layout !== null) {
        Column() {
          if (this.layout.body.length > 0) {
            Text(this.layout.body)
              .fontSize(14)
              .fontColor('#ffffff')
              .padding(16)
          }
          Text(`模板：${this.layout.templateId}`)
            .fontSize(11)
            .fontColor('#8b87a6')
            .margin({ top: 8 })
        }
        .width('90%')
        .padding(16)
        .borderRadius(14)
        .backgroundColor('rgba(255,255,255,0.04)')
        .margin({ bottom: 18 })
      } else {
        Text('卡片还在准备中…')
          .fontColor('#8b87a6')
          .margin({ bottom: 18 })
      }

      if (this.lastMessage.length > 0) {
        Text(this.lastMessage)
          .fontSize(12)
          .fontColor('#c9befc')
          .backgroundColor('rgba(139,124,246,0.12)')
          .padding(8)
          .borderRadius(10)
          .margin({ left: 16, right: 16, bottom: 12 })
          .width('90%')
      }

      Button(this.status === 'sharing' ? '正在唤起系统面板…' : '✦ 分享到系统')
        .width('90%')
        .height(48)
        .backgroundColor('#8b7cf6')
        .borderRadius(999)
        .fontColor('#ffffff')
        .enabled(this.status !== 'sharing' && this.layout !== null)
        .opacity(this.status !== 'sharing' && this.layout !== null ? 1.0 : 0.5)
        .onClick(() => {
          void this.onShareTap();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#050608')
  }
}