import { curves } from '@kit.ArkUI';
import { type Draft } from '../../core/model/Domain';
import { fallbackDiary } from '../conversation/FallbackGuide';
import { TypingDots } from '../ui/TypingDots';
import {
  ConversationController,
  initialConversationState,
  type ConversationState,
} from '../conversation/ConversationController';
import { MiloBackNode, MiloPrimaryButton } from '../ui/MiloButtons';
import { AI_AVAILABLE } from '../../core/config/FeatureFlags';

/** Web `cubic-bezier(0.22, 1, 0.36, 1)`. */
const MILO_EASE: ICurve = curves.cubicBezierCurve(0.22, 1, 0.36, 1);

const INK: string = '#eae6ff';
const INK_DIM: string = 'rgba(234,230,255,0.72)';
const INK_FAINT: string = 'rgba(234,230,255,0.60)';
const INK_INTERACTIVE: string = 'rgba(238,234,255,0.78)';
const GLASS_BG: string = 'rgba(255,255,255,0.06)';
const GLASS_BORDER: string = 'rgba(255,255,255,0.12)';
const PAPER_TEXT: string = 'rgba(240,236,255,0.92)';

/**
 * First-person diary screen, styled 1:1 after the Web `Diary.tsx` page.
 * Prefers the AI gateway via `ConversationController.createDiary`; on any
 * failure the local `fallbackDiary` runs so the user always sees a draft.
 */
@Component
export struct DiaryScreen {
  @State diaryOn: boolean = true;
  @State diary: string = '';
  @State generating: boolean = true;
  @State editing: boolean = false;
  @State conversationState: ConversationState = initialConversationState();
  draft: Draft = { mood: { valence: 0, labels: [] }, transcript: [], diaryEnabled: true };
  controller: ConversationController | null = null;
  onSave: (diary: string | undefined, enabled: boolean) => void = () => {};
  onBack: () => void = () => {};

  aboutToAppear(): void {
    if (!this.diaryOn) {
      this.diary = '';
      this.generating = false;
      return;
    }
    this.generating = true;
    void this.generateDiary();
  }

  private async generateDiary(): Promise<void> {
    if (!AI_AVAILABLE || this.controller === null) {
      this.diary = fallbackDiary(this.draft);
      this.generating = false;
      return;
    }
    const result = await this.controller.createDiary(this.draft);
    this.conversationState = result.state;
    this.diary = result.diary;
    this.generating = false;
  }

  private toggleDiary(): void {
    this.getUIContext().animateTo({ duration: 300, curve: MILO_EASE }, () => {
      this.diaryOn = !this.diaryOn;
    });
    if (this.diaryOn && this.diary.length === 0) {
      this.generating = true;
      void this.generateDiary();
    }
  }

  private fallbackNotice(): string {
    if (!AI_AVAILABLE || this.conversationState.lastError === undefined) {
      return '';
    }
    return 'AI 暂时不可用，已为你用本地模板生成。';
  }

  build() {
    Scroll() {
      Column() {
        Row() {
          MiloBackNode({
            onTap: () => this.onBack(),
          })
          Blank()
          Text(this.draft.timeMark ?? '')
            .fontSize(12)
            .fontColor(INK_FAINT)
            .letterSpacing(5)
          Blank()
            .width(68)
        }
        .width('100%')
        .padding({ bottom: 14 })

        Column() {
          Text('显影这段回忆')
            .fontSize(27)
            .fontFamily('serif')
            .fontWeight(500)
            .fontColor(INK)
            .lineHeight(40)
            .letterSpacing(1)
          Text('读一读，也可以改一改')
            .fontSize(14.5)
            .fontColor(INK_DIM)
            .lineHeight(28)
            .margin({ top: 8 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: 16, bottom: 20 })

        if (this.fallbackNotice().length > 0) {
          Text(this.fallbackNotice())
            .fontSize(12)
            .fontColor('#c9befc')
            .backgroundColor('rgba(139,124,246,0.12)')
            .padding(8)
            .borderRadius(10)
            .margin({ bottom: 10 })
            .width('100%')
        }

        Row() {
          Column() {
            Text('沉淀为日记')
              .fontSize(14.5)
              .fontColor(INK)
            Text('关闭后只保留对话')
              .fontSize(12)
              .fontColor(INK_FAINT)
              .lineHeight(22)
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row() {
            Column()
              .width(22)
              .height(22)
              .borderRadius(11)
              .backgroundColor('#ffffff')
              .margin({ left: this.diaryOn ? 23 : 3 })
          }
          .width(50)
          .height(30)
          .borderRadius(15)
          .linearGradient({
            angle: 135,
            colors: this.diaryOn
              ? [['#8b7cf6', 0], ['#f0a6ca', 1]]
              : [['rgba(255,255,255,0.12)', 0], ['rgba(255,255,255,0.12)', 1]],
          })
          .border({ width: 1, color: GLASS_BORDER })
          .alignItems(VerticalAlign.Center)
          .onClick(() => this.toggleDiary())
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
        .borderRadius(28)
        .backgroundColor(GLASS_BG)
        .border({ width: 1, color: GLASS_BORDER })
        .margin({ bottom: 18 })

        if (this.diaryOn) {
          Column() {
            if (this.generating && this.diary.length === 0) {
              Row({ space: 8 }) {
                Text('回忆正在显影')
                  .fontSize(12)
                  .fontColor(INK_FAINT)
                  .letterSpacing(1)
                TypingDots()
              }
            } else if (this.editing) {
              TextArea({ text: this.diary })
                .onChange((value: string) => {
                  this.diary = value;
                })
                .width('100%')
                .constraintSize({ minHeight: 260 })
                .backgroundColor(Color.Transparent)
                .fontColor(PAPER_TEXT)
                .fontSize(15.5)
                .lineHeight(33)
                .fontFamily('serif')
                .caretColor('#c9befc')
            } else {
              Text(this.diary)
                .fontSize(15.5)
                .lineHeight(33)
                .letterSpacing(1)
                .fontFamily('serif')
                .fontColor(PAPER_TEXT)
                .width('100%')
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 24, right: 24, top: 26, bottom: 26 })
          .borderRadius(28)
          .linearGradient({
            angle: 180,
            colors: [['rgba(255,255,255,0.07)', 0], ['rgba(255,255,255,0.03)', 1]],
          })
          .border({ width: 1, color: GLASS_BORDER })
          .margin({ bottom: 20 })

          if (!this.generating) {
            Button(this.editing ? '完成编辑' : '编辑日记')
              .backgroundColor(Color.Transparent)
              .borderRadius(999)
              .fontColor(INK_DIM)
              .fontSize(15)
              .margin({ bottom: 12 })
              .onClick(() => {
                this.editing = !this.editing;
              })
          }
        }

        MiloPrimaryButton({
          label: '收进回忆',
          active: !this.diaryOn || !this.generating,
          onTap: () => {
            this.onSave(this.diaryOn ? this.diary : undefined, this.diaryOn);
          },
        })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 20, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 900, curve: MILO_EASE }),
    )
  }
}
