import { type ChatMessage, type DiaryEntry, type MoodId } from '../../core/model/Domain';
import { moodWord } from '../conversation/FallbackGuide';
import { MoodPlanet } from '../mood/MoodPlanet';
import { MiloBackNode, MiloPrimaryButton } from '../ui/MiloButtons';

function formatDate(ts: number): string {
  const d = new Date(ts);
  return `${d.getFullYear()} 年 ${d.getMonth() + 1} 月 ${d.getDate()} 日`;
}

@Component
export struct DetailScreen {
  @State showChat: boolean = false;
  entry: DiaryEntry | undefined = undefined;
  onCard: (entryId: string) => void = () => {};
  onBack: () => void = () => {};
  onRemove: (entryId: string) => void = () => {};

  build() {
    Column() {
      Row() {
        MiloBackNode({
          onTap: () => this.onBack(),
        })
        Blank()
        if (this.entry !== undefined) {
          Text(formatDate(this.entry.createdAt))
            .fontColor('#c9befc')
            .fontSize(12)
        }
        Blank()
        Text('放下')
          .fontSize(13)
          .fontColor('#8b87a6')
          .padding({ left: 4, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            if (this.entry !== undefined) {
              this.onRemove(this.entry.id);
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 16, top: 16, bottom: 8 })

      if (this.entry === undefined) {
        Text('这段回忆已经飘走了。')
          .fontColor('#8b87a6')
          .margin({ top: 100 })
      } else {
        Column() {
          Text(this.entry.kind === 'past' ? (this.entry.timeMark ?? '过去的某一天') : '此刻')
            .fontSize(24)
            .fontFamily('serif')
            .fontWeight(FontWeight.Medium)
            .fontColor('#ffffff')
          Text(
            `${moodWord(this.entry.mood.valence, this.entry.mood.emotionId)}` +
              (this.entry.mood.labels.length > 0 ? ` · ${this.entry.mood.labels.join(' · ')}` : '')
          )
            .fontSize(13)
            .fontColor('#8b87a6')
            .margin({ top: 6 })
        }
        .margin({ top: 16, bottom: 24 })

        if (this.entry.mood.emotionId !== undefined) {
          MoodPlanet({ moodId: this.entry.mood.emotionId as MoodId, planetSize: 110 })
        }

        if (this.entry.diary !== undefined && this.entry.diary.length > 0) {
          Text(this.entry.diary)
            .width('90%')
            .padding(18)
            .borderRadius(24)
            .backgroundColor('rgba(255,255,255,0.04)')
            .border({ width: 1, color: 'rgba(255,255,255,0.08)' })
            .fontColor('#ffffff')
            .fontSize(14)
            .lineHeight(22)
            .margin({ top: 24, bottom: 12 })
        } else if (this.entry.note !== undefined && this.entry.note.length > 0) {
          Text(this.entry.note)
            .width('90%')
            .padding(18)
            .borderRadius(24)
            .backgroundColor('rgba(255,255,255,0.04)')
            .border({ width: 1, color: 'rgba(255,255,255,0.08)' })
            .fontColor('#ffffff')
            .fontSize(14)
            .lineHeight(22)
            .margin({ top: 24, bottom: 12 })
        }

        if (this.entry.transcript !== undefined && this.entry.transcript.length > 0) {
          Button(this.showChat ? '收起当时的对话' : '看看当时的对话')
            .backgroundColor(Color.Transparent)
            .borderRadius(999)
            .fontColor('#c9befc')
            .fontSize(14)
            .margin({ top: 12, bottom: 12 })
            .onClick(() => {
              this.showChat = !this.showChat;
            })
          if (this.showChat) {
            Column({ space: 12 }) {
              ForEach(this.entry.transcript, (message: ChatMessage) => {
                Text(message.text)
                  .padding(12)
                  .borderRadius(14)
                  .backgroundColor(message.role === 'user' ? 'rgba(139,124,246,0.20)' : 'rgba(255,255,255,0.06)')
                  .fontColor('#ffffff')
                  .fontSize(14)
                  .maxLines(20)
                  .constraintSize({ maxWidth: '82%' })
              })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ bottom: 18 })
          }
        }

        Blank()

        MiloPrimaryButton({
          label: '生成回忆卡片',
          onTap: () => {
            if (this.entry !== undefined) {
              this.onCard(this.entry.id);
            }
          },
        })
          .margin({ left: 24, right: 24, bottom: 28 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
