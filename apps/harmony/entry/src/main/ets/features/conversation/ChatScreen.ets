import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { type ChatMessage, type Draft } from '../../core/model/Domain';
import { FallbackGuide } from './FallbackGuide';
import { TypingDots } from '../ui/TypingDots';
import {
  ConversationController,
  initialConversationState,
  type ConversationState,
} from './ConversationController';
import { SpeechInput, mergeRecognizedText, speechFeedback, type SpeechResult } from '../../core/system/SpeechInput';
import { HarmonySpeechPlatform } from '../../core/system/HarmonySpeechPlatform';
import { MiloBackNode, MiloPrimaryButton, pathPx } from '../ui/MiloButtons';
import { AI_AVAILABLE, effectiveAiEnabled } from '../../core/config/FeatureFlags';

/** Web `cubic-bezier(0.22, 1, 0.36, 1)` — the signature Milo ease. */
const MILO_EASE: ICurve = curves.cubicBezierCurve(0.22, 1, 0.36, 1);

const INK: string = '#eae6ff';
const INK_FAINT: string = 'rgba(234,230,255,0.60)';
const INK_INTERACTIVE: string = 'rgba(238,234,255,0.78)';
const GLASS_BG: string = 'rgba(255,255,255,0.06)';
const GLASS_BORDER: string = 'rgba(255,255,255,0.12)';

/** Short prompts leave room for the user to keep talking or save at any time. */
@Component
export struct ChatScreen {
  @State messages: ChatMessage[] = [];
  @State input: string = '';
  @State busy: boolean = false;
  @State aiMode: boolean = AI_AVAILABLE;
  defaultAiEnabled: boolean = true;
  onAiSettings: () => void = () => {};
  @State listening: boolean = false;
  @State speechStatus: string = '';
  @State finishingSpeech: boolean = false;
  @State userSpoke: boolean = false;
  @State conversationState: ConversationState = initialConversationState();
  @State sendPressScale: number = 1;
  private active: boolean = false;
  private guide: FallbackGuide | null = null;
  private scroller: Scroller = new Scroller();
  private speech: SpeechInput | null = null;
  private speechTurn: number = 0;
  controller: ConversationController | null = null;
  draft: Draft = { mood: { valence: 0, labels: [] }, transcript: [], diaryEnabled: true };
  onFinish: (transcript: ChatMessage[]) => void = () => {};
  onBack: () => void = () => {};
  onChatChange: (transcript: ChatMessage[], inputText: string, aiEnabled: boolean) => void = () => {};

  aboutToAppear(): void {
    this.active = true;
    this.aiMode = effectiveAiEnabled(this.draft.aiEnabled ?? this.defaultAiEnabled);
    this.input = this.draft.inputText ?? '';
    this.conversationState = initialConversationState();
    this.conversationState.source = this.aiMode ? 'ai' : 'script';
    const timeMark = this.draft.timeMark ?? '过去的某一天';
    this.guide = new FallbackGuide(timeMark);
    this.speech = new SpeechInput({
      platform: new HarmonySpeechPlatform(getContext(this) as common.UIAbilityContext),
    });
    if (this.controller !== null) {
      this.controller.restoreState(this.conversationState);
    }
    this.messages = this.draft.transcript.slice();
    let answered = 0;
    for (let index = 0; index < this.messages.length; index += 1) {
      if (this.messages[index].role === 'user') answered += 1;
    }
    this.userSpoke = answered > 0;
    this.guide.restoreStep(answered);
    this.controller?.restore(answered);
    if (this.messages.length === 0) {
      if (this.aiMode && this.controller !== null) {
        this.busy = true;
        void this.controller.open(this.draft).then((result) => {
          if (!this.active) return;
          this.conversationState = result.state;
          this.pushMessage(result.message);
        }).catch(() => {
          if (this.active && this.guide !== null) this.pushMessage({ role: 'ai', text: this.guide.opening(), ts: Date.now() });
        }).finally(() => { if (this.active) this.busy = false; });
      } else {
        this.pushMessage({ role: 'ai', text: this.guide.opening(), ts: Date.now() });
      }
    } else {
      this.scrollToEnd();
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.speechTurn += 1;
    if (this.speech !== null) {
      void this.speech.dispose();
      this.speech = null;
    }
  }

  private async sendReply(draft: Draft, text: string, ts: number): Promise<void> {
    if (this.aiMode && this.controller !== null) {
      // A transient failure must not permanently disable future AI attempts.
      this.controller.restoreState({ source: 'ai', fallbackStep: this.guide?.currentStep() ?? 0, lastError: undefined });
      this.controller.restore(this.guide?.currentStep() ?? 0);
      const result = await this.controller.respond(draft, text, ts);
      if (!this.active) return;
      this.conversationState = result.state;
      this.guide?.restoreStep(result.state.fallbackStep);
      this.pushMessage(result.message);
      return;
    }
    this.pushLocalReply(text);
  }

  private pushLocalReply(text: string): void {
    if (this.guide !== null && this.active) {
      this.pushMessage({ role: 'ai', text: this.guide.next(text), ts: Date.now() });
    }
  }

  private toggleAi(): void {
    if (!AI_AVAILABLE || this.busy || this.listening) return;
    this.aiMode = !this.aiMode;
    if (this.aiMode) {
      this.conversationState = initialConversationState();
      this.conversationState.fallbackStep = this.guide?.currentStep() ?? 0;
      this.controller?.restoreState(this.conversationState);
    } else {
      this.conversationState.source = 'script';
      this.controller?.restoreState(this.conversationState);
    }
    this.persistChat();
  }

  private finish(): void {
    if (!this.canFinish()) return;
    if (!this.aiMode) {
      this.controller?.restoreState({
        source: 'script',
        fallbackStep: this.guide?.currentStep() ?? 0,
        lastError: undefined,
      });
    } else {
      this.controller?.restoreState({ source: 'ai', fallbackStep: this.guide?.currentStep() ?? 0, lastError: undefined });
    }
    this.active = false;
    this.onFinish(this.messages);
  }

  private persistChat(): void {
    const preference = AI_AVAILABLE ? this.aiMode : (this.draft.aiEnabled ?? this.defaultAiEnabled);
    this.onChatChange(this.messages, this.input, preference);
  }

  private pushMessage(message: ChatMessage): void {
    const next: ChatMessage[] = [];
    for (let index = 0; index < this.messages.length; index += 1) {
      next.push(this.messages[index]);
    }
    next.push(message);
    this.messages = next;
    this.persistChat();
    this.scrollToEnd();
  }

  private scrollToEnd(): void {
    setTimeout(() => {
      if (this.active) this.scroller.scrollEdge(Edge.Bottom);
    }, 60);
  }

  private canFinish(): boolean {
    return this.userSpoke && !this.busy && !this.listening && this.input.trim().length === 0;
  }

  private toggleMic(): void {
    const speech = this.speech;
    if (speech === null || this.busy) {
      return;
    }
    if (this.listening) {
      if (this.finishingSpeech) return;
      this.finishingSpeech = true;
      this.speechStatus = '正在整理识别结果…';
      void speech.finish();
      return;
    }
    this.listening = true;
    this.finishingSpeech = false;
    this.speechStatus = '正在准备语音识别…';
    const turn = ++this.speechTurn;
    const prior = this.input;
    speech
      .begin((result: SpeechResult) => {
        if (!this.active || turn !== this.speechTurn) return;
        if (!this.finishingSpeech && (result.state === 'listening' || result.state === 'recognizing')) {
          this.speechStatus = '正在聆听，说完后稍停，或再次点击麦克风结束。';
        }
        if (result.text.trim().length > 0) this.input = mergeRecognizedText(prior, result.text);
      })
      .then((result: SpeechResult) => {
        if (!this.active || turn !== this.speechTurn) return;
        this.listening = false;
        this.finishingSpeech = false;
        this.speechStatus = speechFeedback(result);
        if (result.text.trim().length > 0) {
          this.input = mergeRecognizedText(prior, result.text);
          this.persistChat();
        }
      })
      .catch(() => {
        if (!this.active || turn !== this.speechTurn) return;
        this.listening = false;
        this.finishingSpeech = false;
        this.speechStatus = '语音识别暂不可用，请重试或使用键盘输入。';
      });
  }

  private canSend(): boolean {
    return this.input.trim().length > 0 && !this.busy && !this.listening;
  }

  private sendGradientStops(): Array<[ResourceColor, number]> {
    if (this.canSend()) {
      return [['rgba(139,124,246,1)', 0], ['rgba(240,166,202,0.9)', 1]];
    }
    return [['rgba(255,255,255,0.06)', 0], ['rgba(255,255,255,0.06)', 1]];
  }

  private animateSendPress(pressed: boolean): void {
    this.getUIContext().animateTo(
      { duration: 180, curve: curves.springMotion(0.38, 0.7) },
      () => {
        this.sendPressScale = pressed ? 0.94 : 1;
      },
    );
  }

  private sendCurrent(): void {
    if (!this.canSend()) return;
    const text = this.input.trim();
    const ts = Date.now();
    // The controller appends this turn; send it all earlier messages exactly once.
    const context: Draft = {
      mood: this.draft.mood,
      kind: this.draft.kind,
      timeMark: this.draft.timeMark,
      transcript: this.messages.slice(),
      diaryEnabled: this.draft.diaryEnabled,
    };
    this.input = '';
    this.busy = true;
    this.userSpoke = true;
    this.pushMessage({ role: 'user', text: text, ts: ts });
    void this.sendReply(context, text, ts)
      .catch(() => this.pushLocalReply(text))
      .finally(() => {
        if (this.active) this.busy = false;
      });
  }

  build() {
    Column() {
      Row() {
        MiloBackNode({
          onTap: () => this.onBack(),
        })
        if (AI_AVAILABLE) {
          Text(this.aiMode ? '✦ AI 开' : 'AI 关')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.aiMode ? '#050608' : '#8b87a6')
          .backgroundColor(this.aiMode ? '#8b7cf6' : 'rgba(139,124,246,0.14)')
          .borderRadius(13)
          .height(36)
          .padding({ left: 10, right: 10 })
          .margin({ left: 12 })
          .onClick(() => {
            this.toggleAi();
          })
        }
        Blank()
        Text(this.draft.timeMark ?? '')
          .fontSize(12)
          .fontColor(INK_FAINT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '40%' })
        Blank()
        Text(this.aiMode && this.conversationState.source === 'ai' ? '回响' : '引导')
          .fontSize(12)
          .fontColor(INK_FAINT)
          .width(48)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      .padding({ bottom: 14 })

      if (AI_AVAILABLE) {
        Row({ space: 10 }) {
          Text(this.busy && this.aiMode ? '正在连接 AI，请稍候…' :
            (this.aiMode ? (this.conversationState.lastError?.message ?? 'AI 已开启，下一条消息将使用当前模型。') : 'AI 已关闭，正在使用本地引导。'))
            .fontSize(12).fontColor('#c9befc').layoutWeight(1).maxLines(3)
          Text('AI 设置').fontSize(13).fontColor('#b9aefc').padding(8)
            .enabled(!this.busy).onClick(() => { this.persistChat(); this.onAiSettings(); })
        }.width('100%').margin({ bottom: 10 })
      }

      List({ space: 14, scroller: this.scroller }) {
        ForEach(this.messages, (message: ChatMessage) => {
          ListItem() {
            Row() {
              Text(message.text)
                .fontSize(16)
                .lineHeight(28)
                .fontColor(INK)
                .padding({ left: 17, right: 17, top: 13, bottom: 13 })
                .borderRadius({
                  topLeft: 20,
                  topRight: 20,
                  bottomLeft: message.role === 'ai' ? 6 : 20,
                  bottomRight: message.role === 'user' ? 6 : 20,
                })
                .backgroundColor(message.role === 'user' ? 'rgba(255,255,255,0.09)' : 'rgba(139,124,246,0.14)')
                .border({
                  width: 1,
                  color: message.role === 'user' ? 'rgba(255,255,255,0.13)' : 'rgba(139,124,246,0.25)',
                })
                .constraintSize({ maxWidth: message.role === 'user' ? '88%' : '82%' })
                .transition(
                  TransitionEffect.OPACITY
                    .combine(TransitionEffect.translate({ y: 10 }))
                    .animation({ duration: 500, curve: MILO_EASE }),
                )
            }
            .width('100%')
            .justifyContent(message.role === 'user' ? FlexAlign.End : FlexAlign.Start)
          }
        }, (message: ChatMessage, index: number) => `${index}-${message.ts}-${message.role}`)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 2, right: 2, top: 8, bottom: 16 })

      if (this.busy) {
        Column() {
          TypingDots()
        }
        .padding({ left: 17, right: 17, top: 13, bottom: 13 })
        .borderRadius({ topLeft: 20, topRight: 20, bottomLeft: 6, bottomRight: 20 })
        .backgroundColor('rgba(139,124,246,0.14)')
        .border({ width: 1, color: 'rgba(139,124,246,0.25)' })
        .alignSelf(ItemAlign.Start)
        .width(72)
      }

      if (this.canFinish()) {
        MiloPrimaryButton({
          label: '保存这段回忆',
          onTap: () => this.finish(),
        })
          .margin({ bottom: 12 })
      }

      Column() {
        if (this.speechStatus.length > 0) {
          Text(this.speechStatus)
            .fontSize(12)
            .fontColor(INK_FAINT)
            .width('100%')
            .margin({ bottom: 8 })
        }
        Row({ space: 10 }) {
          Column({ space: 1 }) {
            Column()
              .width(13)
              .height(16)
              .borderRadius(7)
              .backgroundColor(this.listening ? '#050608' : INK_INTERACTIVE)
            Column()
              .width(16)
              .height(9)
              .borderRadius({ bottomLeft: 8, bottomRight: 8 })
              .border({
                width: { left: 1.5, right: 1.5, bottom: 1.5 },
                color: this.listening ? '#050608' : INK_INTERACTIVE,
              })
            Column()
              .width(1.5)
              .height(3)
              .backgroundColor(this.listening ? '#050608' : INK_INTERACTIVE)
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(this.listening ? '#8b7cf6' : GLASS_BG)
          .border({
            width: 1,
            color: this.listening ? 'rgba(139,124,246,0.6)' : GLASS_BORDER,
          })
          .shadow(this.listening ? { radius: 22, color: 'rgba(139,124,246,0.55)' } : {
            radius: 0,
            color: 'rgba(0,0,0,0)',
          })
          .scale(this.listening ? { x: 1.06, y: 1.06 } : { x: 1, y: 1 })
          .accessibilityText(this.listening ? '结束语音输入' : '开始语音输入')
          .onClick(() => {
            this.toggleMic();
          })

          TextArea({
            placeholder: this.listening ? '正在聆听…' : '想说什么都可以…',
            text: this.input,
          })
            .enabled(!this.listening)
            .onChange((value: string) => {
              this.input = value;
              this.persistChat();
            })
            .enterKeyType(EnterKeyType.NEW_LINE)
            .layoutWeight(1)
            .height(76)
            .padding({ left: 8, right: 8, top: 10, bottom: 10 })
            .backgroundColor(Color.Transparent)
            .fontColor(INK)
            .fontSize(16)
            .placeholderColor('rgba(234,230,255,0.64)')
            .placeholderFont({ size: 15 })
            .caretColor('#c9befc')

          Stack() {
            Column()
              .width('100%')
              .height('100%')
              .linearGradient({
                angle: 135,
                colors: this.sendGradientStops(),
              })
            Path({ width: 44, height: 44 })
              .commands(`M${pathPx(12)} ${pathPx(12.5)} L${pathPx(31.5)} ${pathPx(21)} L${pathPx(12)} ${pathPx(29.5)} Z`)
              .fill(this.canSend() ? '#ffffff' : 'rgba(234,230,255,0.55)')
            Path({ width: 44, height: 44 })
              .commands(`M${pathPx(12)} ${pathPx(19.2)} L${pathPx(25.5)} ${pathPx(21)} L${pathPx(12)} ${pathPx(22.8)}`)
              .fillOpacity(0)
              .stroke(this.canSend() ? 'rgba(139,124,246,0.55)' : 'rgba(18,15,36,0.5)')
              .strokeWidth(1.2)
              .strokeLineCap(LineCapStyle.Round)
              .strokeLineJoin(LineJoinStyle.Round)
          }
          .width(44)
          .height(44)
          .borderRadius(22)
          .border({ width: 1, color: this.canSend() ? 'rgba(255,255,255,0)' : GLASS_BORDER })
          .shadow(this.canSend() ? { radius: 20, color: 'rgba(139,124,246,0.45)', offsetY: 4 } : {
            radius: 0,
            color: 'rgba(0,0,0,0)',
          })
          .scale({ x: this.sendPressScale, y: this.sendPressScale })
          .accessibilityText('发送')
          .onClick(() => {
            this.sendCurrent();
          })
          .onTouch((event: TouchEvent) => {
            if (!this.canSend()) {
              return;
            }
            if (event.type === TouchType.Down) {
              this.animateSendPress(true);
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.animateSendPress(false);
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding(10)
        .borderRadius(24)
        .backgroundColor(GLASS_BG)
        .border({ width: 1, color: GLASS_BORDER })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 24 })
    .transition(
      TransitionEffect.OPACITY
        .combine(TransitionEffect.translate({ y: 12 }))
        .animation({ duration: 900, curve: MILO_EASE }),
    )
  }
}
