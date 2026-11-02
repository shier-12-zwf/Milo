import { curves } from '@kit.ArkUI';

/**
 * Deterministic starfield used as the home / empty-state backdrop.
 * Positions are seeded so screenshots stay stable across runs.
 *
 * Tapping empty background scatters nearby stars outward like grains of
 * sand (spring burst), then they drift back home along the settle curve.
 */
export interface Star {
  x: number; // 0..1 horizontal fraction
  y: number; // 0..1 vertical fraction
  radius: number; // px radius
  opacity: number; // 0..1
}

/** A star plus its current scatter displacement; mutated in place so
 *  @ObjectLink children animate attribute changes. */
@Observed
export class StarView {
  star: Star;
  dx: number;
  dy: number;
  dim: number;
  driftX: number = 0;
  driftY: number = 0;
  twinkle: number = 1;

  constructor(star: Star, dx: number, dy: number, dim: number) {
    this.star = star;
    this.dx = dx;
    this.dy = dy;
    this.dim = dim;
  }
}

@Component
struct StarItem {
  @ObjectLink view: StarView;
  color: string = '#ffffff';

  build() {
    Circle({ width: this.view.star.radius * 2, height: this.view.star.radius * 2 })
      .fill(this.color)
      .opacity(this.view.twinkle * (1 - this.view.dim))
      .position({ x: `${this.view.star.x * 100}%`, y: `${this.view.star.y * 100}%` })
      .translate({ x: this.view.dx + this.view.driftX, y: this.view.dy + this.view.driftY })
  }
}

const SCATTER_RADIUS_VP = 170;
const SCATTER_MAG_VP = 36;
const SCATTER_BURST_DELAY_MS = 420;

function seedFrom(seed: number): () => number {
  let state = seed >>> 0;
  return (): number => {
    if (state === 0) {
      state = 0x9e3779b9;
    }
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    return ((state >>> 0) % 100000) / 100000;
  };
}

/** Returns `count` stars with stable positions for the given seed. */
export function generateStars(count: number, seed: number): Star[] {
  const rand = seedFrom(seed);
  const out: Star[] = [];
  for (let index = 0; index < count; index += 1) {
    const x = rand();
    const y = rand();
    const size = rand();
    const fade = rand();
    out.push({
      x: x,
      y: y,
      radius: 0.3 + size * 1.3,
      opacity: 0.25 + fade * 0.6,
    });
  }
  return out;
}

const DEFAULT_STARFIELD: Star[] = generateStars(120, 0x5a17c0fe);

@Component
export struct Starfield {
  @Prop count: number = 120;
  @Prop seed: number = 0x5a17c0fe;
  @Prop color: string = '#dcd6ff';
  @State views: Array<StarView> = [];
  private fieldWidth: number = 0;
  private fieldHeight: number = 0;
  private settleTimer: number = -1;
  private motionTimer: number = -1;
  private elapsed: number = 0;
  private lastFrame: number = 0;

  private startMotion(): void {
    if (this.motionTimer >= 0) return;
    this.lastFrame = Date.now();
    this.motionTimer = setInterval(() => {
      const now = Date.now();
      const delta = Math.min((now - this.lastFrame) / 1000, 0.1);
      this.lastFrame = now;
      this.elapsed += delta;
      for (let index = 0; index < this.views.length; index += 1) {
        const view = this.views[index];
        const phase = view.star.x * Math.PI * 2;
        const speed = 0.4 + view.star.y * 1.2;
        view.twinkle = 0.25 + 0.55 * Math.abs(Math.sin(phase + this.elapsed * speed));
        // Web drift is per 60 Hz frame; integrate seconds for any refresh rate.
        const drift = (view.star.opacity - 0.55) * 0.1 * 60 * delta;
        view.driftX += drift * 0.6;
        view.driftY -= drift;
        const x = view.star.x * this.fieldWidth + view.driftX;
        const y = view.star.y * this.fieldHeight + view.driftY;
        if (x < -4) view.driftX += this.fieldWidth + 8;
        if (x > this.fieldWidth + 4) view.driftX -= this.fieldWidth + 8;
        if (y < -4) view.driftY += this.fieldHeight + 8;
        if (y > this.fieldHeight + 4) view.driftY -= this.fieldHeight + 8;
      }
    }, 33);
  }

  private stopMotion(): void {
    if (this.motionTimer >= 0) clearInterval(this.motionTimer);
    this.motionTimer = -1;
  }

  private computeStars(): Star[] {
    if (this.count === 0) {
      if (this.fieldWidth <= 0 || this.fieldHeight <= 0) return [];
      return generateStars(Math.max(1, Math.floor(this.fieldWidth * this.fieldHeight / 4200)), this.seed);
    }
    if (this.count === DEFAULT_STARFIELD.length && this.seed === 0x5a17c0fe) {
      return DEFAULT_STARFIELD;
    }
    return generateStars(this.count, this.seed);
  }

  private zeroedViews(): Array<StarView> {
    const stars = this.computeStars();
    const out: Array<StarView> = [];
    for (let index = 0; index < stars.length; index += 1) {
      out.push(new StarView(stars[index], 0, 0, 0));
    }
    return out;
  }

  aboutToAppear(): void {
    this.views = this.zeroedViews();
  }

  aboutToDisappear(): void {
    this.stopMotion();
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
      this.settleTimer = -1;
    }
  }

  /** Sand burst: stars near the tap point are pushed radially outward. */
  private handleTap(event: ClickEvent): void {
    if (this.fieldWidth <= 0 || this.fieldHeight <= 0) {
      return;
    }
    this.getUIContext().animateTo(
      { curve: curves.springMotion(0.3, 0.55) },
      () => {
        this.applyScatter(event.x, event.y);
      },
    );
    if (this.settleTimer >= 0) {
      clearTimeout(this.settleTimer);
    }
    this.settleTimer = setTimeout(() => {
      this.getUIContext().animateTo(
        { duration: 640, curve: curves.cubicBezierCurve(0.22, 0.72, 0.18, 1) },
        () => {
          this.clearScatter();
        },
      );
      this.settleTimer = -1;
    }, SCATTER_BURST_DELAY_MS);
  }

  /** Mutates star views in place so @ObjectLink items animate the change. */
  private applyScatter(tapX: number, tapY: number): void {
    for (let index = 0; index < this.views.length; index += 1) {
      const view = this.views[index];
      const ddx = view.star.x * this.fieldWidth + view.driftX - tapX;
      const ddy = view.star.y * this.fieldHeight + view.driftY - tapY;
      const dist = Math.hypot(ddx, ddy);
      if (dist > 0.001 && dist < SCATTER_RADIUS_VP) {
        const falloff = 1 - dist / SCATTER_RADIUS_VP;
        const mag = SCATTER_MAG_VP * falloff * falloff;
        view.dx = (ddx / dist) * mag;
        view.dy = (ddy / dist) * mag;
        view.dim = 0.45 * falloff;
      } else {
        view.dx = 0;
        view.dy = 0;
        view.dim = 0;
      }
    }
  }

  private clearScatter(): void {
    for (let index = 0; index < this.views.length; index += 1) {
      const view = this.views[index];
      view.dx = 0;
      view.dy = 0;
      view.dim = 0;
    }
  }

  build() {
    Stack() {
      ForEach(this.views, (view: StarView, index: number) => {
        StarItem({ view: view, color: this.color })
      }, (view: StarView, index: number) => index.toString())
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onVisibleAreaChange([0], (_visible: boolean, ratio: number) => {
      if (ratio > 0) this.startMotion();
      else this.stopMotion();
    })
    .onClick((event: ClickEvent) => {
      this.handleTap(event);
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.fieldWidth = Number(newArea.width);
      this.fieldHeight = Number(newArea.height);
      if (this.count === 0) this.views = this.zeroedViews();
      if (this.fieldWidth > 0 && this.fieldHeight > 0) this.startMotion();
    })
  }
}
