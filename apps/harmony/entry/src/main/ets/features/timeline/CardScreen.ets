import { componentSnapshot, curves, display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import {
  type DiaryEntry,
  type StickerTemplateId,
  DEFAULT_STICKER_TEMPLATE,
} from '../../core/model/Domain';
import {
  STICKER_TEMPLATES,
  normalizeStickerTemplate,
  type StickerTemplateMeta,
} from '../../core/system/CardRenderer';
import {
  drawCardArt,
  measureCardDesignHeight,
  CARD_DESIGN_WIDTH,
  CARD_DESIGN_HEIGHT,
  ORBIT_THEATRE_DESIGN_HEIGHT,
  type CardArtworkImage,
} from '../../core/system/CardArt';
import { getMoodAsset, type MoodAssetSheetName } from '../../core/model/MoodAssets';

/** Web `cubic-bezier(0.22, 1, 0.36, 1)`. */
const MILO_EASE: ICurve = curves.cubicBezierCurve(0.22, 1, 0.36, 1);

const INK: string = '#eae6ff';
const INK_FAINT: string = 'rgba(234,230,255,0.60)';
const INK_INTERACTIVE: string = 'rgba(238,234,255,0.78)';
// Security components force backgrounds below 10% opacity to fully opaque.
const SAVE_BUTTON_BG: string = '#252237';

const SHEET_RESOURCES: Record<MoodAssetSheetName, Resource> = {
  'mood_sheet_01': $r('app.media.mood_sheet_01'),
  'mood_sheet_02': $r('app.media.mood_sheet_02'),
  'mood_sheet_03': $r('app.media.mood_sheet_03'),
  'mood_sheet_04': $r('app.media.mood_sheet_04'),
  'mood_sheet_05': $r('app.media.mood_sheet_05'),
};

/**
 * Both sticker templates are rendered live on ArkUI canvases with a shared
 * design grid and density-independent typography (see `CardArt.ets`). The main
 * preview can be saved into the system gallery through the SaveButton
 * security component; template choice is persisted via `onSelect`.
 */
@Component
export struct CardScreen {
  @State selected: StickerTemplateId = DEFAULT_STICKER_TEMPLATE;
  @State previewWidth: number = 286;
  @State previewHeight: number = 358;
  @State thumbWidth: number = 145;
  @State saveState: string = '';
  entry: DiaryEntry | undefined = undefined;
  onSelect: (template: StickerTemplateId) => void = () => {};
  onDone: () => void = () => {};
  onHome: () => void = () => {};
  private ctxPreview: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ctxThumbA: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private ctxThumbB: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private artworkImage: CardArtworkImage | null = null;
  private previewReady: boolean = false;
  private thumbAReady: boolean = false;
  private thumbBReady: boolean = false;

  aboutToAppear(): void {
    const win: display.Display = display.getDefaultDisplaySync();
    const winVp: number = win.width / win.densityPixels;
    this.previewWidth = Math.min(winVp - 48, 460);
    this.thumbWidth = Math.floor((winVp - 48 - 10) / 2) - 14;
    this.selected = normalizeStickerTemplate(
      this.entry !== undefined ? this.entry.stickerTemplate : undefined,
    );
    void this.loadArtwork();
  }

  private async loadArtwork(): Promise<void> {
    const entry = this.entry;
    if (entry === undefined || entry.mood.emotionId === undefined) {
      console.info(`milo-card: artwork skipped (entry=${entry !== undefined}, emotionId=${entry !== undefined ? entry.mood.emotionId : 'none'})`);
      return;
    }
    const asset = getMoodAsset(entry.mood.emotionId);
    if (asset === undefined) {
      console.info('milo-card: artwork skipped (no asset)');
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const raw: Uint8Array = context.resourceManager.getMediaContentSync(SHEET_RESOURCES[asset.sheet]);
      console.info(`milo-card: sheet=${asset.sheet} bytes=${raw.byteLength} offset=${raw.byteOffset}`);
      // getMediaContentSync may return a view into a larger buffer; hand the
      // decoder an exact copy so a non-zero byteOffset cannot corrupt the PNG.
      const bytes: ArrayBuffer = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
      const source: image.ImageSource = image.createImageSource(bytes);
      const pixelMap: image.PixelMap = await source.createPixelMap();
      const info: image.ImageInfo = await pixelMap.getImageInfo();
      console.info(`milo-card: pixelMap ${info.size.width}x${info.size.height}`);
      this.artworkImage = {
        pixelMap: pixelMap,
        pixelWidth: info.size.width,
        pixelHeight: info.size.height,
      };
      this.drawPreview();
      this.drawThumb(0);
      this.drawThumb(1);
    } catch (e) {
      // Keep the gradient-orb fallback; the card still renders without art.
      console.info(`milo-card: artwork load failed: ${(e as BusinessError).message}`);
    }
  }

  private drawPreview(): void {
    const entry = this.entry;
    if (entry === undefined || !this.previewReady) {
      return;
    }
    const ctx = this.ctxPreview;
    const designHeight: number = measureCardDesignHeight(ctx, entry, this.selected);
    const targetHeight: number = this.previewWidth * designHeight / CARD_DESIGN_WIDTH;
    if (Math.abs(targetHeight - this.previewHeight) > 0.5) {
      // Resize first; onAreaChange triggers the redraw at the new height.
      this.previewHeight = targetHeight;
      return;
    }
    const scale: number = this.previewWidth / CARD_DESIGN_WIDTH;
    ctx.clearRect(0, 0, this.previewWidth, this.previewHeight);
    ctx.save();
    ctx.scale(scale, scale);
    drawCardArt(ctx, designHeight, entry, this.selected, this.artworkImage);
    ctx.restore();
  }

  private drawThumb(index: number): void {
    const entry = this.entry;
    if (entry === undefined) {
      return;
    }
    if (index === 0 && !this.thumbAReady) {
      return;
    }
    if (index !== 0 && !this.thumbBReady) {
      return;
    }
    const ctx = index === 0 ? this.ctxThumbA : this.ctxThumbB;
    const templateId: StickerTemplateId = index === 0
      ? STICKER_TEMPLATES[0].id
      : STICKER_TEMPLATES[1].id;
    const baseHeight: number = templateId === 'planet-letter'
      ? CARD_DESIGN_HEIGHT
      : ORBIT_THEATRE_DESIGN_HEIGHT;
    const width: number = this.thumbWidth;
    const height: number = width * 5 / 8;
    const scale: number = width / CARD_DESIGN_WIDTH;
    ctx.clearRect(0, 0, width, height);
    ctx.save();
    ctx.scale(scale, scale);
    drawCardArt(ctx, baseHeight, entry, templateId, this.artworkImage);
    ctx.restore();
  }

  private selectTemplate(templateId: StickerTemplateId): void {
    if (templateId === this.selected || this.saveState === 'saving') {
      return;
    }
    this.selected = templateId;
    this.saveState = '';
    this.onSelect(templateId);
    this.drawPreview();
  }

  private selectedOrdinal(): string {
    for (let index = 0; index < STICKER_TEMPLATES.length; index += 1) {
      if (STICKER_TEMPLATES[index].id === this.selected) {
        return `${index + 1}`;
      }
    }
    return '1';
  }

  private saveStatusText(): string {
    if (this.saveState === 'saving') {
      return '正在保存…';
    }
    if (this.saveState === 'saved') {
      return '已保存到系统图库。';
    }
    return '保存失败，请重试。';
  }

  private async saveToGallery(): Promise<void> {
    if (this.saveState === 'saving' || this.entry === undefined || !this.previewReady) {
      return;
    }
    this.saveState = 'saving';
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const density: number = display.getDefaultDisplaySync().densityPixels;
      const exportScale: number = Math.max(1, CARD_DESIGN_WIDTH / (this.previewWidth * density));
      const pixelMap: image.PixelMap = await componentSnapshot.get('miloCardPreview', {
        scale: exportScale,
        waitUntilRenderFinished: true,
      });
      const packer: image.ImagePacker = image.createImagePacker();
      const data: ArrayBuffer = await packer.packing(pixelMap, { format: 'image/png', quality: 100 });
      await packer.release();
      await pixelMap.release();
      const path: string = `${context.cacheDir}/milo-card-${Date.now()}.png`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data);
      fs.closeSync(file);
      const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
      const request: photoAccessHelper.MediaAssetChangeRequest =
        photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, `file://${path}`);
      await helper.applyChanges(request);
      this.saveState = 'saved';
    } catch (e) {
      this.saveState = 'failed';
    }
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Row() {
            Text('← 完成')
              .fontSize(14)
              .fontColor(INK_INTERACTIVE)
              .onClick(() => this.onDone())
          }
          .width('100%')
          .padding({ bottom: 14 })

          Column() {
            Text('MILO MEMORY')
              .fontSize(12)
              .fontColor(INK_FAINT)
              .letterSpacing(4)
              .margin({ bottom: 7 })
            Text('你的情绪卡片')
              .fontSize(27)
              .fontFamily('serif')
              .fontWeight(500)
              .fontColor(INK)
              .lineHeight(36.5)
            Text('把这颗星球，分享给今天的世界。')
              .fontSize(13)
              .fontColor('rgba(234,230,255,0.72)')
              .margin({ top: 5 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .margin({ top: 2, bottom: 18 })

          Column() {
            if (this.entry !== undefined) {
              Canvas(this.ctxPreview)
                .width(this.previewWidth)
                .height(this.previewHeight)
                .borderRadius(23)
                .clip(true)
                .border({ width: 1, color: 'rgba(255,255,255,0.11)' })
                .shadow({ radius: 54, color: 'rgba(139,124,246,0.14)' })
                .id('miloCardPreview')
                .onReady(() => {
                  this.previewReady = true;
                  this.drawPreview();
                })
                .onAreaChange((oldValue: Area, newValue: Area) => {
                  this.drawPreview();
                })
                .transition(
                  TransitionEffect.OPACITY
                    .combine(TransitionEffect.translate({ y: 7 }))
                    .animation({ duration: 460, curve: MILO_EASE }),
                )
            } else {
              Column() {
                Text('卡片还在准备中…')
                  .fontSize(12)
                  .fontColor(INK_FAINT)
                  .letterSpacing(1.7)
              }
              .width(this.previewWidth)
              .aspectRatio(0.8)
              .borderRadius(23)
              .backgroundColor('rgba(255,255,255,0.035)')
              .border({ width: 1, color: 'rgba(255,255,255,0.09)' })
              .justifyContent(FlexAlign.Center)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .margin({ bottom: 20 })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            const width: number = Number(newValue.width);
            const previewWidth: number = Math.min(width, 460);
            if (width > 0 && Math.abs(this.previewWidth - previewWidth) > 0.5) {
              this.previewWidth = previewWidth;
              this.thumbWidth = Math.floor((width - 10) / 2) - 14;
              this.drawPreview();
              this.drawThumb(0);
              this.drawThumb(1);
            }
          })

          Row() {
            Column() {
              Text('LAYOUTS')
                .fontSize(9)
                .fontColor(INK_FAINT)
                .letterSpacing(1.8)
                .margin({ bottom: 2 })
              Text('选择卡片模板')
                .fontSize(16)
                .fontFamily('serif')
                .fontWeight(500)
                .fontColor(INK)
                .lineHeight(22)
                .letterSpacing(0.6)
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            Text(`${this.selectedOrdinal()} / ${STICKER_TEMPLATES.length}`)
              .fontSize(9)
              .fontColor(INK_FAINT)
              .letterSpacing(1.8)
          }
          .width('100%')
          .padding({ left: 2, right: 2 })
          .margin({ bottom: 11 })

          Row({ space: 10 }) {
            ForEach(STICKER_TEMPLATES, (template: StickerTemplateMeta, index: number) => {
              Stack({ alignContent: Alignment.TopStart }) {
                Column() {
                  Canvas(index === 0 ? this.ctxThumbA : this.ctxThumbB)
                    .width('100%')
                    .aspectRatio(1.6)
                    .borderRadius(9)
                    .clip(true)
                    .backgroundColor('rgba(255,255,255,0.045)')
                    .onReady(() => {
                      if (index === 0) {
                        this.thumbAReady = true;
                      } else {
                        this.thumbBReady = true;
                      }
                      this.drawThumb(index);
                    })
                  Text(template.name)
                    .fontSize(14)
                    .fontFamily('serif')
                    .fontColor(INK)
                    .letterSpacing(0.4)
                    .margin({ top: 8, left: 2, right: 2 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(template.tone)
                    .fontSize(12)
                    .fontColor(INK_FAINT)
                    .letterSpacing(0.6)
                    .margin({ left: 2, right: 2, bottom: 2 })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding(7)

                Text(`0${index + 1}`)
                  .fontSize(8)
                  .fontColor('rgba(255,255,255,0.76)')
                  .letterSpacing(0.6)
                  .textAlign(TextAlign.Center)
                  .width(24)
                  .height(17)
                  .borderRadius(999)
                  .backgroundColor('rgba(6,6,15,0.48)')
                  .border({ width: 1, color: 'rgba(255,255,255,0.16)' })
                  .margin({ top: 12, left: 12 })
              }
              .layoutWeight(1)
              .borderRadius(15)
              .border({
                width: 1,
                color: template.id === this.selected
                  ? 'rgba(186,171,255,0.72)'
                  : 'rgba(255,255,255,0.1)',
              })
              .linearGradient(template.id === this.selected
                ? {
                    angle: 180,
                    colors: [['rgba(166,147,255,0.19)', 0], ['rgba(12,11,29,0.78)', 1]],
                  }
                : {
                    angle: 180,
                    colors: [['rgba(30,30,52,0.62)', 0], ['rgba(8,8,21,0.58)', 1]],
                  })
              .shadow(template.id === this.selected
                ? { radius: 28, color: 'rgba(29,22,64,0.28)', offsetY: 9 }
                : { radius: 0, color: 'rgba(0,0,0,0)' })
              .animation({ duration: 240, curve: Curve.Ease })
              .onClick(() => {
                this.selectTemplate(template.id);
              })
            }, (template: StickerTemplateMeta) => template.id)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 12 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      if (this.saveState.length > 0) {
        Text(this.saveStatusText())
          .fontSize(12)
          .fontColor(this.saveState === 'failed' ? '#f4c4d4' : '#c9befc')
          .margin({ bottom: 8 })
      }

      Row({ space: 12 }) {
        Column() {
          SaveButton({ text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Capsule })
            .width('100%')
            .height(48)
            .borderRadius(999)
            .backgroundColor(SAVE_BUTTON_BG)
            .borderWidth(1)
            .borderColor('rgba(255,255,255,0.14)')
            .borderStyle(BorderStyle.Solid)
            .fontColor(INK)
            .fontSize(15)
            .onClick((event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                void this.saveToGallery();
              }
            })
        }
        .layoutWeight(1)

        Column() {
          Button('回到首页')
            .height(48)
            .width('100%')
            .borderRadius(999)
            .backgroundColor(Color.Transparent)
            .linearGradient({
              angle: 135,
              colors: [['rgba(139,124,246,0.85)', 0], ['rgba(240,166,202,0.72)', 1]],
            })
            .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
            .fontColor('#ffffff')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.onHome())
        }
        .layoutWeight(1)
      }
      .width('100%')
      .padding(10)
      .margin({ left: 20, right: 20, bottom: 16 })
      .borderRadius(20)
      .backgroundColor('rgba(7,7,18,0.76)')
      .border({ width: 1, color: 'rgba(213,205,244,0.14)' })
      .shadow({ radius: 54, color: 'rgba(0,0,0,0.46)', offsetY: 18 })
    }
    .width('100%')
    .height('100%')
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 900, curve: MILO_EASE }),
    )
  }
}
