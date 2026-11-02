import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MiloBackNode } from '../ui/MiloButtons';

/**
 * Web `Classify.tsx` 1:1 — the two fork cards (now vs. past) with the serif
 * card titles, quiet glass first card and the violet-glow echo card.
 */
@Component
export struct ClassifyScreen {
  onNow: () => void = () => {};
  onPast: () => void = () => {};
  onBack: () => void = () => {};

  build() {
    Column() {
      Row() {
        MiloBackNode({
          onTap: () => this.onBack(),
        })
      }
      .width('100%')
      .padding({ left: 20, top: 16, bottom: 8 })

      Column() {
        Text('这份感受，来自哪里？')
          .fontSize(24)
          .fontFamily('serif')
          .fontWeight(FontWeight.Medium)
          .fontColor(MILO_COLORS.ink)
        Text('此刻，还是过去？')
          .fontSize(13)
          .fontColor(MILO_COLORS.inkHint)
          .margin({ top: 12 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 28, bottom: 36 })

      Column({ space: 18 }) {
        Column() {
          Text('它属于此刻')
            .fontSize(19)
            .fontFamily('serif')
            .fontWeight(FontWeight.Medium)
            .fontColor(MILO_COLORS.ink)
            .alignSelf(ItemAlign.Start)
          Text('记下现在的心情')
            .fontSize(13)
            .lineHeight(23.4)
            .fontColor(MILO_COLORS.inkDim)
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(24)
        .borderRadius(28)
        .backgroundColor('rgba(255,255,255,0.05)')
        .border({ width: 1, color: 'rgba(255,255,255,0.09)' })
        .shadow({ radius: 30, color: 'rgba(0,0,0,0.22)', offsetY: 10 })
        .onClick(() => this.onNow())

        Column() {
          Text('它来自过去')
            .fontSize(19)
            .fontFamily('serif')
            .fontWeight(FontWeight.Medium)
            .fontColor('#c9befc')
            .alignSelf(ItemAlign.Start)
          Text('聊聊想起的那段时光')
            .fontSize(13)
            .lineHeight(23.4)
            .fontColor(MILO_COLORS.inkDim)
            .margin({ top: 8 })
            .alignSelf(ItemAlign.Start)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(24)
        .borderRadius(28)
        .backgroundColor('rgba(139,124,246,0.09)')
        .border({ width: 1, color: 'rgba(139,124,246,0.4)' })
        .shadow({ radius: 34, color: 'rgba(139,124,246,0.16)', offsetY: 10 })
        .onClick(() => this.onPast())
      }
      .padding({ left: 24, right: 24 })
    }
    .width('100%')
    .height('100%')
  }
}
