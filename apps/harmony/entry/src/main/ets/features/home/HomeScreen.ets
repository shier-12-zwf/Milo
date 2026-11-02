import { ECHO_SELECTOR_MOODS, getMoodDescriptorWords, type MoodDefinition, type MoodId } from '../../core/model/Moods';
import { MILO_COLORS, MILO_TYPOGRAPHY } from '../../core/theme/MiloTheme';
import { MoodOrbitCarousel } from '../mood/MoodOrbitCarousel';
import { MoodPlanet } from '../mood/MoodPlanet';
import { MiloBackLink, MiloBackNode, MiloPrimaryButton, MILO_EASE } from '../ui/MiloButtons';
import { Haptics } from '../../core/system/Haptics';
import { gestureLocalPoint } from '../mood/GesturePoint';

// Web word ring: 360px dial, 136px word radius — scaled to the 377vp screen.
const RING_SIZE = 330;
const RING_CENTER = RING_SIZE / 2;
const WORD_RADIUS = 128;
const PLANET_SIZE = 144;
const MAX_PICKED_WORDS = 3;

type HomeStep = 'feel' | 'word';

/**
 * Web `Home.tsx` two-step selector, 1:1. Step one is the echo orbit carousel
 * with the「就是这种感觉」primary action; step two is the rotating word ring
 * where up to three descriptor labels can be collected before continuing.
 */
@Component
export struct HomeScreen {
  @Prop entryCount: number = 0;
  @State step: HomeStep = 'feel';
  @State activeMoodIndex: number = 3;
  @State ringAngle: number = 0;
  @State smooth: boolean = false;
  @State pickedWords: string[] = [];
  onNext: (moodId: MoodId, labels: string[]) => void = () => {};
  onOpenTimeline: () => void = () => {};
  onOpenAccount: () => void = () => {};
  private haptics: Haptics = new Haptics();
  private lastDragAngle: number = 0;
  private hasDragPoint: boolean = false;

  private activeMood(): MoodDefinition {
    return ECHO_SELECTOR_MOODS[this.activeMoodIndex];
  }

  private descriptorWords(): string[] {
    const mood = this.activeMood();
    return getMoodDescriptorWords(mood.id, mood.valence);
  }

  private wordStepAngle(): number {
    const count = this.descriptorWords().length;
    return count > 0 ? 360 / count : 360;
  }

  private focusIndex(): number {
    const words = this.descriptorWords();
    const step = this.wordStepAngle();
    let best = 0;
    let bestDiff = 361;
    for (let index = 0; index < words.length; index += 1) {
      let a = (index * step - 90 + this.ringAngle) % 360;
      if (a < 0) {
        a += 360;
      }
      const diff = Math.min(Math.abs(a - 270), 360 - Math.abs(a - 270));
      if (diff < bestDiff) {
        bestDiff = diff;
        best = index;
      }
    }
    return best;
  }

  private isPicked(word: string): boolean {
    for (let index = 0; index < this.pickedWords.length; index += 1) {
      if (this.pickedWords[index] === word) {
        return true;
      }
    }
    return false;
  }

  private toggleWord(word: string): void {
    const next: string[] = [];
    let removed = false;
    for (let index = 0; index < this.pickedWords.length; index += 1) {
      if (this.pickedWords[index] !== word) {
        next.push(this.pickedWords[index]);
      } else {
        removed = true;
      }
    }
    if (!removed && this.pickedWords.length < MAX_PICKED_WORDS) {
      next.push(word);
    }
    if (next.length !== this.pickedWords.length || removed) {
      this.haptics.selection();
      this.pickedWords = next;
    }
  }

  private dragAngle(event: GestureEvent): number | null {
    const point = gestureLocalPoint(event);
    if (point === null || Math.hypot(point.y - RING_CENTER, point.x - RING_CENTER) < 12) return null;
    return Math.atan2(point.y - RING_CENTER, point.x - RING_CENTER) * 180 / Math.PI;
  }

  private settleRing(): void {
    const step = this.wordStepAngle();
    const target = Math.round(this.ringAngle / step) * step;
    this.smooth = true;
    this.getUIContext().animateTo({ duration: 400, curve: MILO_EASE }, () => {
      this.ringAngle = target;
    });
  }

  private goStep(step: HomeStep): void {
    // Every trip from the mood dial begins a fresh word selection.
    this.pickedWords = [];
    this.getUIContext().animateTo({ duration: 420, curve: MILO_EASE }, () => {
      this.step = step;
    });
    if (step === 'word') {
      this.ringAngle = 0;
      this.smooth = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('MILO-米洛')
          .fontSize(MILO_TYPOGRAPHY.eyebrowSize)
          .fontColor(MILO_COLORS.inkHint)
          .letterSpacing(5)
        Blank()
        MiloBackLink({
          label: this.entryCount > 0 ? `回忆 · ${this.entryCount}` : '回忆',
          onTap: () => this.onOpenTimeline(),
        })
        MiloBackLink({ label: '我的', onTap: () => this.onOpenAccount() })
          .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16, bottom: 8 })

      if (this.step === 'feel') {
        Column() {
          Text('此刻，你感受到的是？')
            .fontSize(24)
            .fontColor(MILO_COLORS.ink)
            .margin({ top: 16, bottom: 4 })
          Text('点选最贴近的一颗星，我们陪你继续')
            .fontSize(MILO_TYPOGRAPHY.subtitleSize)
            .fontColor(MILO_COLORS.inkHint)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Blank()
        MoodOrbitCarousel({
          onSelect: (index: number) => {
            this.activeMoodIndex = index;
          },
          onActiveChange: (index: number) => {
            this.activeMoodIndex = index;
          },
        })
        Blank()

        Text(this.activeMood().labels[0])
          .fontSize(22)
          .fontFamily('serif')
          .fontWeight(FontWeight.Medium)
          .fontColor(MILO_COLORS.ink)
          .margin({ bottom: 6 })
        Text('沿圆环旋转，或点击任意情绪直接切换')
          .fontSize(12)
          .fontColor(MILO_COLORS.inkHint)
          .margin({ bottom: 22 })

        MiloPrimaryButton({
          label: '就是这种感觉',
          onTap: () => this.goStep('word'),
        })
          .margin({ left: 24, right: 24, bottom: 24 })
      } else {
        Column() {
          MiloBackNode({
            onTap: () => this.goStep('feel'),
          })
            .alignSelf(ItemAlign.Start)
            .margin({ left: 4, top: 4 })
          Text('如果要给它一个名字')
            .fontSize(22)
            .fontFamily('serif')
            .fontWeight(FontWeight.Medium)
            .fontColor(MILO_COLORS.ink)
            .margin({ top: 2 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        Blank()

        Stack() {
          MoodPlanet({ moodId: this.activeMood().id, planetSize: PLANET_SIZE })

          ForEach(this.descriptorWords(), (word: string, index: number) => {
            Stack({ alignContent: Alignment.TopEnd }) {
              Text(word)
                .fontSize(this.wordHighlighted(word, index) ? 19 : 14)
                .fontFamily(this.wordHighlighted(word, index) ? 'serif' : 'sans-serif')
                .fontWeight(this.wordHighlighted(word, index) ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.wordColor(word, index))
                .textShadow(
                  this.wordHighlighted(word, index)
                    ? { radius: 18, color: 'rgba(255,255,255,0.45)' }
                    : { radius: 0, color: 'rgba(0,0,0,0)' },
                )
                .letterSpacing(1)
                .width('100%')
                .height('100%')
                .textAlign(TextAlign.Center)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              if (this.isPicked(word)) {
                Circle({ width: 5, height: 5 })
                  .fill('#b9aefc')
                  .shadow({ radius: 8, color: '#b9aefc' })
                  .offset({ x: -4, y: 4 })
              }
            }
            .width(84)
            .height(40)
            .markAnchor({ x: '50%', y: '50%' })
            .position({ x: this.wordX(index), y: this.wordY(index) })
            .onClick(() => {
              this.toggleWord(word);
            })
          }, (word: string) => word)
        }
        .width(RING_SIZE)
        .height(RING_SIZE)
        .gesture(
          PanGesture({ fingers: 1 })
            .onActionStart((event: GestureEvent) => {
              this.smooth = false;
              const angle = this.dragAngle(event);
              this.hasDragPoint = angle !== null;
              if (angle !== null) this.lastDragAngle = angle;
            })
            .onActionUpdate((event: GestureEvent) => {
              const angle = this.dragAngle(event);
              if (angle === null) return;
              if (!this.hasDragPoint) {
                this.hasDragPoint = true;
                this.lastDragAngle = angle;
                return;
              }
              let delta = angle - this.lastDragAngle;
              if (delta > 180) {
                delta -= 360;
              }
              if (delta < -180) {
                delta += 360;
              }
              this.ringAngle += delta;
              this.lastDragAngle = angle;
            })
            .onActionEnd(() => {
              this.hasDragPoint = false;
              this.settleRing();
            })
            .onActionCancel(() => {
              this.hasDragPoint = false;
              this.settleRing();
            }),
        )

        Text('旋转词环，轻点收下最贴切的词（最多 3 个）')
          .fontSize(12)
          .fontColor(MILO_COLORS.inkHint)
          .margin({ top: 18 })

        Column() {
          if (this.pickedWords.length > 0) {
            Text(this.pickedWords.join(' · '))
              .fontSize(15)
              .fontColor('#c9befc')
          }
        }
        .height(30)
        .justifyContent(FlexAlign.Center)
        .margin({ top: 12, bottom: 14 })

        MiloPrimaryButton({
          label: '继续',
          onTap: () => {
            const labels = this.pickedWords.slice();
            this.pickedWords = [];
            this.step = 'feel';
            this.onNext(this.activeMood().id, labels);
          },
        })
          .margin({ left: 24, right: 24 })

        Text('也可以不选任何词，感受不必都有名字')
          .fontSize(12)
          .fontColor(MILO_COLORS.inkHint)
          .margin({ top: 12, bottom: 16 })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  private wordColor(word: string, index: number): string {
    if (this.wordHighlighted(word, index)) {
      return '#ffffff';
    }
    return 'rgba(234,230,255,0.60)';
  }

  private wordHighlighted(word: string, index: number): boolean {
    return this.isPicked(word) || index === this.focusIndex();
  }

  private wordX(index: number): number {
    const angle = (index * this.wordStepAngle() - 90 + this.ringAngle) * Math.PI / 180;
    return RING_CENTER + Math.cos(angle) * WORD_RADIUS;
  }

  private wordY(index: number): number {
    const angle = (index * this.wordStepAngle() - 90 + this.ringAngle) * Math.PI / 180;
    return RING_CENTER + Math.sin(angle) * WORD_RADIUS;
  }
}
