import { curves } from '@kit.ArkUI';
import { ECHO_SELECTOR_MOODS, type MoodDefinition, type MoodId } from '../../core/model/Moods';
import {
  activeMoodIndex,
  ECHO_MOOD_ORBIT_TRAVEL_PX,
  moodOrbitTextPose,
  moodPointerAngle,
  moodPositionFromRotation,
  moodTickAngle,
  moodTickOpacity,
  nearestMoodPosition,
  orbitalMoodPose,
  projectMoodSnap,
  shortestMoodAngleDelta,
  wrapMoodIndex,
} from './MoodSwipeModel';
import { MoodPlanet } from './MoodPlanet';
import { MOOD_SHEET_HEIGHT, MOOD_SHEET_WIDTH } from '../../core/model/MoodAssets';
import { Haptics } from '../../core/system/Haptics';
import { gestureLocalPoint } from './GesturePoint';

// Web reference: 300px dial scaled by 240/300 = 0.8.
const RING_DIAMETER = 240;
// Web: ticks translateY(-143px) -> 143 * 0.8.
const TICK_RADIUS = 114;
// Web: words translateY(-174px) -> 174 * 0.8.
const WORD_RADIUS = 139;
// Web reference: orb 244 on a 300 dial (81%); keep the same ratio on the 240 ring.
const PLANET_SIZE = 195;
const PLANET_HEIGHT = PLANET_SIZE * (MOOD_SHEET_HEIGHT / MOOD_SHEET_WIDTH);
// Web layering: orb z=30, ticks z=44, words z=46.
const TICK_Z_INDEX = 44;
const WORD_Z_INDEX = 46;
const CAROUSEL_SIZE = RING_DIAMETER + ECHO_MOOD_ORBIT_TRAVEL_PX * 2;
const RING_CENTER = CAROUSEL_SIZE / 2;
const MOOD_LIST: Array<MoodDefinition> = ECHO_SELECTOR_MOODS as Array<MoodDefinition>;
// Web reference: 28px dead zone on a 300px dial, scaled to our 240px ring.
const DRAG_DEAD_ZONE_VP = 22;
const SETTLE_DURATION_MS = 520;
const VELOCITY_WINDOW_MS = 100;
// Web tick style: 28px hit box with a 1px bar; active bar is taller and glows.
const STEP_BOX_SIZE = 22;
const STEP_BAR_WIDTH = 1;
const STEP_BAR_HEIGHT = 10;
const STEP_BAR_HEIGHT_ACTIVE = 18;
const STEP_BAR_TOP = 5.6;
const STEP_BAR_TOP_ACTIVE = 2.4;
const STEP_BAR_COLOR = 'rgba(205,210,223,0.58)';
const STEP_BAR_COLOR_ACTIVE = 'rgba(246,247,250,0.96)';
// Web word style: 14px base / 28px active, scaled by 0.8.
const WORD_FONT_SIZE = 11;
const WORD_FONT_SIZE_ACTIVE = 22;
const WORD_COLOR_NEGATIVE = 'rgba(194,205,229,0.82)';
const WORD_COLOR_POSITIVE = 'rgba(241,220,190,0.86)';
const WORD_COLOR_NEUTRAL = 'rgba(231,230,236,0.9)';
const WORD_COLOR_ACTIVE = 'rgba(240,241,246,0.94)';
// Web ring: dotted border, brighter while expanded / dragging.
const RING_STROKE_COLOR = 'rgba(221,225,235,0.22)';
const RING_STROKE_COLOR_DRAGGING = 'rgba(232,236,246,0.34)';

interface Point {
  x: number;
  y: number;
}

/** One rotation sample used to estimate fling velocity. */
interface RotationSample {
  rotation: number;
  time: number;
}

/** Result callback when the user taps a mood. */
type SelectCallback = (index: number) => void;

/**
 * Echo-style continuous carousel: a ring of fifteen mood ticks, an orb at the
 * focus point, and an expandable word ring. Reuses the same math as the Web
 * build so positions and opacities match exactly.
 */
@Component
export struct MoodOrbitCarousel {
  @State dialPosition: number = 3;
  @State expanded: boolean = true;
  @State dragging: boolean = false;
  onSelect: SelectCallback = (_index: number) => {};
  onActiveChange: SelectCallback = (_index: number) => {};
  private haptics: Haptics = new Haptics();
  private lastActiveIndex: number = 3;
  private gestureStartPosition: number = 3;
  private lastPointerAngle: number = 0;
  private hasPointerAngle: boolean = false;
  private accumulatedRotation: number = 0;
  private samples: Array<RotationSample> = [];

  private count(): number {
    return ECHO_SELECTOR_MOODS.length;
  }

  private activeIndex(): number {
    return activeMoodIndex(this.dialPosition, this.count());
  }

  /**
   * Single write path for the dial position. Fires the selection haptic and
   * notifies the host whenever the focused mood crosses a step boundary,
   * mirroring the web build's `updateEchoPosition`.
   */
  private updatePosition(next: number): void {
    this.dialPosition = next;
    const index = this.activeIndex();
    if (index !== this.lastActiveIndex) {
      this.lastActiveIndex = index;
      this.haptics.selection();
      this.onActiveChange(index);
    }
  }

  /** Animated settle used after fling, cancel and deliberate taps. */
  private settleTo(target: number): void {
    this.getUIContext().animateTo(
      {
        duration: SETTLE_DURATION_MS,
        curve: curves.cubicBezierCurve(0.22, 0.72, 0.18, 1),
      },
      () => {
        this.dragging = false;
        this.updatePosition(target);
      },
    );
  }

  private rememberSample(rotation: number, time: number): void {
    this.samples.push({ rotation: rotation, time: time });
    this.samples = this.samples.filter((sample: RotationSample) => time - sample.time <= VELOCITY_WINDOW_MS);
  }

  private trackPointer(event: GestureEvent, emit: boolean): void {
    const point = gestureLocalPoint(event);
    if (point === null) return;
    const dx = point.x - RING_CENTER;
    const dy = point.y - RING_CENTER;
    if (Math.hypot(dx, dy) < DRAG_DEAD_ZONE_VP) {
      return;
    }
    const angle = moodPointerAngle(point.x, point.y, RING_CENTER, RING_CENTER);
    if (!this.hasPointerAngle) {
      this.hasPointerAngle = true;
      this.lastPointerAngle = angle;
      this.rememberSample(this.accumulatedRotation, Date.now());
      return;
    }
    this.accumulatedRotation += shortestMoodAngleDelta(this.lastPointerAngle, angle);
    this.lastPointerAngle = angle;
    this.rememberSample(this.accumulatedRotation, Date.now());
    if (emit) {
      this.updatePosition(
        moodPositionFromRotation(this.gestureStartPosition, this.accumulatedRotation, this.count()),
      );
    }
  }

  private handleDragStart(event: GestureEvent): void {
    this.gestureStartPosition = this.dialPosition;
    this.accumulatedRotation = 0;
    this.hasPointerAngle = false;
    this.samples = [];
    this.dragging = true;
    this.trackPointer(event, false);
  }

  private handleDragUpdate(event: GestureEvent): void {
    this.trackPointer(event, true);
  }

  private positionVelocityPerMs(): number {
    const sampleCount = this.samples.length;
    if (sampleCount < 2) {
      return 0;
    }
    const first = this.samples[0];
    const last = this.samples[sampleCount - 1];
    const elapsed = last.time - first.time;
    if (elapsed <= 0) {
      return 0;
    }
    const rotationVelocity = (last.rotation - first.rotation) / elapsed;
    return -rotationVelocity / (360 / this.count());
  }

  private handleDragEnd(): void {
    const target = projectMoodSnap(this.dialPosition, this.positionVelocityPerMs());
    this.settleTo(target);
  }

  private handleDragCancel(): void {
    this.settleTo(projectMoodSnap(this.dialPosition, 0));
  }

  /** Animated select used by tick and word taps (web: `selectEchoMood`). */
  private selectIndex(index: number): void {
    this.expanded = true;
    this.settleTo(nearestMoodPosition(this.dialPosition, index, this.count()));
    this.onSelect(index);
  }

  private activeMoodId(): MoodId {
    return MOOD_LIST[this.activeIndex()].id;
  }

  private activeOrbOffsetX(): number {
    const pose = orbitalMoodPose(this.activeIndex(), this.dialPosition, this.count());
    return pose.x;
  }

  private activeOrbOffsetY(): number {
    const pose = orbitalMoodPose(this.activeIndex(), this.dialPosition, this.count());
    return pose.y;
  }

  private activeOrbScale(): number {
    const pose = orbitalMoodPose(this.activeIndex(), this.dialPosition, this.count());
    return pose.scale;
  }

  private activeOrbZ(): number {
    const pose = orbitalMoodPose(this.activeIndex(), this.dialPosition, this.count());
    return pose.zIndex;
  }

  private tickPoint(angle: number, radius: number): Point {
    const radians = (angle - 90) * (Math.PI / 180);
    const out: Point = {
      x: Math.cos(radians) * radius,
      y: Math.sin(radians) * radius,
    };
    return out;
  }

  private isTickActive(index: number): boolean {
    return wrapMoodIndex(index, this.count()) === this.activeIndex();
  }

  private tickBarHeight(index: number): number {
    return this.isTickActive(index) ? STEP_BAR_HEIGHT_ACTIVE : STEP_BAR_HEIGHT;
  }

  private tickBarTop(index: number): number {
    return this.isTickActive(index) ? STEP_BAR_TOP_ACTIVE : STEP_BAR_TOP;
  }

  private tickBarColor(index: number): string {
    return this.isTickActive(index) ? STEP_BAR_COLOR_ACTIVE : STEP_BAR_COLOR;
  }

  private tickOpacityValue(index: number): number {
    return moodTickOpacity(index, this.dialPosition, this.count());
  }

  private tickX(index: number): number {
    const angle = moodTickAngle(index, this.dialPosition, this.count());
    const point = this.tickPoint(angle, TICK_RADIUS);
    return RING_CENTER + point.x;
  }

  private tickY(index: number): number {
    const angle = moodTickAngle(index, this.dialPosition, this.count());
    const point = this.tickPoint(angle, TICK_RADIUS);
    return RING_CENTER + point.y;
  }

  private wordPose(index: number) {
    return moodOrbitTextPose(index, this.dialPosition, this.count(), this.expanded);
  }

  private wordPoseVisible(index: number): boolean {
    return this.wordPose(index).visible;
  }

  private wordOpacity(index: number): number {
    return this.wordPose(index).opacity;
  }

  private wordScale(index: number): number {
    return this.wordPose(index).scale;
  }

  /** Web: active word jumps to 28px (not transitioned), others stay at 14px. */
  private wordFontSize(index: number): number {
    return this.isTickActive(index) ? WORD_FONT_SIZE_ACTIVE : WORD_FONT_SIZE;
  }

  /** Web: color follows polarity; the active word brightens. */
  private wordColor(index: number): string {
    if (this.isTickActive(index)) {
      return WORD_COLOR_ACTIVE;
    }
    const valence = MOOD_LIST[index].valence;
    if (valence < 0) {
      return WORD_COLOR_NEGATIVE;
    }
    if (valence > 0) {
      return WORD_COLOR_POSITIVE;
    }
    return WORD_COLOR_NEUTRAL;
  }

  private wordX(index: number): number {
    const pose = this.wordPose(index);
    const point = this.tickPoint(pose.angle, WORD_RADIUS);
    return RING_CENTER + point.x;
  }

  private wordY(index: number): number {
    const pose = this.wordPose(index);
    const point = this.tickPoint(pose.angle, WORD_RADIUS);
    return RING_CENTER + point.y;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Circle({ width: RING_DIAMETER, height: RING_DIAMETER })
        .fill(Color.Transparent)
        .stroke(this.dragging ? RING_STROKE_COLOR_DRAGGING : RING_STROKE_COLOR)
        .strokeWidth(this.dragging ? 1.5 : 1)
        .scale({ x: this.dragging ? 1.025 : 1, y: this.dragging ? 1.025 : 1 })

      ForEach(MOOD_LIST, (mood: MoodDefinition, index: number) => {
        // Web mood-orbit-step: 28px hit box with a thin bar crossing the ring.
        Stack() {
          Column()
            .width(STEP_BAR_WIDTH)
            .height(this.tickBarHeight(index))
            .backgroundColor(this.tickBarColor(index))
            .borderRadius(1)
            .position({
              x: (STEP_BOX_SIZE - STEP_BAR_WIDTH) / 2,
              y: this.tickBarTop(index),
            })
        }
        .width(STEP_BOX_SIZE)
        .height(STEP_BOX_SIZE)
        .opacity(this.tickOpacityValue(index))
        .position({ x: this.tickX(index), y: this.tickY(index) })
        .markAnchor({ x: '50%', y: '50%' })
        .zIndex(TICK_Z_INDEX)
        .onClick(() => {
          this.selectIndex(index);
        })
      })

      ForEach(MOOD_LIST, (mood: MoodDefinition, index: number) => {
        Text(mood.labels[0])
          .fontSize(this.wordFontSize(index))
          .fontColor(this.wordColor(index))
          .fontFamily('serif')
          .opacity(this.wordOpacity(index))
          .scale({ x: this.wordScale(index), y: this.wordScale(index) })
          .position({ x: this.wordX(index), y: this.wordY(index) })
          .markAnchor({ x: '50%', y: '50%' })
          .textShadow({
            radius: 22,
            color: 'rgba(205,211,233,0.18)',
            offsetX: 0,
            offsetY: 0,
          })
          .zIndex(WORD_Z_INDEX)
          .visibility(this.wordPoseVisible(index) ? Visibility.Visible : Visibility.Hidden)
          .onClick(() => {
            this.selectIndex(index);
          })
      })

      MoodPlanet({ moodId: this.activeMoodId(), planetSize: PLANET_SIZE })
        .position({
          x: RING_CENTER - PLANET_SIZE / 2 + this.activeOrbOffsetX(),
          y: RING_CENTER - PLANET_HEIGHT / 2 + this.activeOrbOffsetY(),
        })
        .scale({ x: this.activeOrbScale(), y: this.activeOrbScale() })
        .zIndex(this.activeOrbZ())
        .onClick(() => {
          this.haptics.selection();
          this.onSelect(this.activeIndex());
        })
    }
    .width(CAROUSEL_SIZE)
    .height(CAROUSEL_SIZE)
    .gesture(
      PanGesture({ fingers: 1, direction: PanDirection.All, distance: 5 })
        .onActionStart((event: GestureEvent) => {
          this.handleDragStart(event);
        })
        .onActionUpdate((event: GestureEvent) => {
          this.handleDragUpdate(event);
        })
        .onActionEnd(() => {
          this.handleDragEnd();
        })
        .onActionCancel(() => {
          this.handleDragCancel();
        })
    )
  }
}
