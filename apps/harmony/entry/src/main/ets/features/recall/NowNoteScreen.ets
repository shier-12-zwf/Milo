import { type MoodState } from '../../core/model/Domain';
import { MILO_COLORS } from '../../core/theme/MiloTheme';
import { MoodPlanet } from '../mood/MoodPlanet';
import { MiloBackNode, MiloPrimaryButton } from '../ui/MiloButtons';

/**
 * Note input for the "now" branch. A planet echoes the picked mood; the note
 * is optional. Styling follows Web `NowNote.tsx`.
 */
@Component
export struct NowNoteScreen {
  @State note: string = '';
  mood: MoodState = { valence: 0, labels: [] };
  onSave: (note: string) => void = () => {};
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
        Text('记下此刻')
          .fontSize(24)
          .fontFamily('serif')
          .fontWeight(FontWeight.Medium)
          .fontColor(MILO_COLORS.ink)
        Text('想写多少都可以')
          .fontSize(13)
          .fontColor(MILO_COLORS.inkHint)
          .margin({ top: 10 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 24, bottom: 28 })

      if (this.mood.emotionId !== undefined) {
        MoodPlanet({ moodId: this.mood.emotionId, planetSize: 120 })
      }

      TextArea({ placeholder: '此刻的感受…（选填）', text: this.note })
        .onChange((value: string) => {
          this.note = value;
        })
        .width('82%')
        .height(120)
        .margin({ top: 24 })
        .padding(16)
        .borderRadius(24)
        .backgroundColor('rgba(255,255,255,0.05)')
        .border({ width: 1, color: 'rgba(255,255,255,0.10)' })
        .fontColor(MILO_COLORS.ink)
        .fontSize(16)
        .placeholderColor('rgba(234,230,255,0.45)')

      Blank()

      MiloPrimaryButton({
        label: '收藏这一刻',
        onTap: () => this.onSave(this.note.trim()),
      })
        .margin({ left: 24, right: 24, bottom: 28 })
    }
    .width('100%')
    .height('100%')
  }
}
