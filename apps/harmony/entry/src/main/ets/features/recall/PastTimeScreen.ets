import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MiloBackNode, MiloPrimaryButton } from '../ui/MiloButtons';
import { Haptics } from '../../core/system/Haptics';

const PRESETS: string[] = [
  '昨天',
  '上个星期',
  '几个月前',
  '去年这个时候',
  '去年夏天',
  '几年前',
  '大学时光',
  '刚工作那会儿',
  '少年时代',
  '小时候',
];

/**
 * Time picker for the "past" branch, styled after Web `PastTime.tsx`:
 * pill chips (radius 999) with the violet glow on-state, a glass text
 * input and the gradient primary action.
 */
@Component
export struct PastTimeScreen {
  @State picked: string = '';
  @State custom: string = '';
  onNext: (timeMark: string) => void = () => {};
  onBack: () => void = () => {};
  private haptics: Haptics = new Haptics();

  private mark(): string {
    const trimmed = this.custom.trim();
    return trimmed.length > 0 ? trimmed : this.picked;
  }

  private isOn(preset: string): boolean {
    return this.picked === preset && this.custom.trim().length === 0;
  }

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
        Text('那是什么时候的事？')
          .fontSize(24)
          .fontFamily('serif')
          .fontWeight(FontWeight.Medium)
          .fontColor(MILO_COLORS.ink)
        Text('大概的时间就好')
          .fontSize(13)
          .lineHeight(23.4)
          .fontColor(MILO_COLORS.inkHint)
          .margin({ top: 12 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 24, bottom: 30 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        ForEach(PRESETS, (preset: string) => {
          Text(preset)
            .fontSize(13.5)
            .padding({ left: 18, right: 18, top: 9, bottom: 9 })
            .margin({ right: 8, bottom: 10 })
            .borderRadius(999)
            .fontColor(this.isOn(preset) ? '#eae6ff' : 'rgba(234,230,255,0.72)')
            .backgroundColor(
              this.isOn(preset) ? 'rgba(139,124,246,0.22)' : 'rgba(255,255,255,0.05)',
            )
            .border({
              width: 1,
              color: this.isOn(preset) ? 'rgba(139,124,246,0.8)' : 'rgba(255,255,255,0.10)',
            })
            .shadow(this.isOn(preset) ? { radius: 18, color: 'rgba(139,124,246,0.35)' } : {
              radius: 0,
              color: 'rgba(0,0,0,0)',
            })
            .onClick(() => {
              this.haptics.selection();
              this.picked = preset;
              this.custom = '';
            })
        }, (preset: string) => preset)
      }
      .width('100%')
      .padding({ left: 28, right: 28 })
      .margin({ bottom: 26 })

      TextInput({ placeholder: '比如，高三的雨季', text: this.custom })
        .onChange((value: string) => {
          this.custom = value;
        })
        .width('82%')
        .height(48)
        .padding({ left: 18, right: 18 })
        .borderRadius(999)
        .backgroundColor('rgba(255,255,255,0.05)')
        .border({ width: 1, color: 'rgba(255,255,255,0.10)' })
        .fontColor(MILO_COLORS.ink)
        .fontSize(14)
        .placeholderColor('rgba(234,230,255,0.45)')
        .placeholderFont({ size: 13 })

      Blank()

      MiloPrimaryButton({
        label: '回到那时',
        active: this.mark().length > 0,
        onTap: () => {
          const value = this.mark();
          if (value.length > 0) {
            this.onNext(value);
          }
        },
      })
        .margin({ left: 24, right: 24, bottom: 28 })
    }
    .width('100%')
    .height('100%')
  }
}
