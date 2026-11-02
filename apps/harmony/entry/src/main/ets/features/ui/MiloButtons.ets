import { curves, display } from '@kit.ArkUI';
import { Starfield } from '../mood/Starfield';

/** Web `cubic-bezier(0.22, 1, 0.36, 1)` — the signature Milo ease. */
export const MILO_EASE: ICurve = curves.cubicBezierCurve(0.22, 1, 0.36, 1);

let cachedDensity: number = 0;

/**
 * Path `commands` render at physical px scale, unlike every other length in
 * ArkUI (which is vp). Convert vp design coordinates to px so vector glyphs
 * keep their intended size on any density.
 */
export function pathPx(vp: number): number {
  if (cachedDensity <= 0) {
    cachedDensity = display.getDefaultDisplaySync().densityPixels;
  }
  return vp * cachedDensity;
}

const INK: string = '#eae6ff';
const INK_INTERACTIVE: string = 'rgba(238,234,255,0.78)';

interface PressableOptions {
  height: number;
  radius: number;
}

/**
 * Web `.btn.btn-primary` — violet→rose gradient, white sheen, pill radius.
 * Apple-style press feedback (scale 0.97) is built in.
 */
@Component
export struct MiloPrimaryButton {
  @Prop label: string = '';
  @Prop active: boolean = true;
  @State pressScale: number = 1;
  onTap: () => void = () => {};

  private animatePress(pressed: boolean): void {
    this.getUIContext().animateTo(
      { duration: 130, curve: curves.springMotion(0.32, 0.6) },
      () => {
        this.pressScale = pressed ? 0.97 : 1;
      },
    );
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 135,
          colors: [['rgba(139,124,246,0.85)', 0], ['rgba(240,166,202,0.72)', 1]],
        })
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(255,255,255,0.22)', 0], ['rgba(255,255,255,0.02)', 0.5]],
        })
      Text(this.label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor('#ffffff')
        .letterSpacing(1.2)
    }
    .width('100%')
    .height(52)
    .borderRadius(999)
    .clip(true)
    .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
    .shadow({ radius: 32, color: 'rgba(139,124,246,0.4)', offsetY: 8 })
    .opacity(this.active ? 1 : 0.48)
    .scale({ x: this.pressScale, y: this.pressScale })
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
    .onTouch((event: TouchEvent) => {
      if (!this.active) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.animatePress(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.animatePress(false);
      }
    })
  }
}

/**
 * Web `.btn` — frosted glass pill with a top sheen and hairline border.
 */
@Component
export struct MiloGlassButton {
  @Prop label: string = '';
  @Prop active: boolean = true;
  @Prop heightVp: number = 48;
  @State pressScale: number = 1;
  onTap: () => void = () => {};

  private animatePress(pressed: boolean): void {
    this.getUIContext().animateTo(
      { duration: 130, curve: curves.springMotion(0.32, 0.6) },
      () => {
        this.pressScale = pressed ? 0.97 : 1;
      },
    );
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            ['rgba(255,255,255,0.12)', 0],
            ['rgba(255,255,255,0.04)', 0.45],
            ['rgba(255,255,255,0.02)', 1],
          ],
        })
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(255,255,255,0.16)', 0], ['rgba(255,255,255,0)', 0.42]],
        })
      Text(this.label)
        .fontSize(15)
        .fontColor(INK)
        .letterSpacing(1.2)
    }
    .width('100%')
    .height(this.heightVp)
    .borderRadius(999)
    .border({ width: 1, color: 'rgba(255,255,255,0.14)' })
    .shadow({ radius: 26, color: 'rgba(0,0,0,0.28)', offsetY: 8 })
    .opacity(this.active ? 1 : 0.48)
    .scale({ x: this.pressScale, y: this.pressScale })
    .onClick(() => {
      if (this.active) {
        this.onTap();
      }
    })
    .onTouch((event: TouchEvent) => {
      if (!this.active) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.animatePress(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.animatePress(false);
      }
    })
  }
}

/** Web `.back-link` — quiet text action used in every topbar. */
@Component
export struct MiloBackLink {
  @Prop label: string = '← 返回';
  onTap: () => void = () => {};

  build() {
    Text(this.label)
      .fontSize(14)
      .fontColor(INK_INTERACTIVE)
      .padding({ left: 4, right: 8, top: 6, bottom: 6 })
      .onClick(() => this.onTap())
  }
}

/**
 * Circular glass back node with a bold "<" chevron — the iOS-style navigation
 * back control used in every topbar. Frosted-glass container with springy
 * press feedback (scale 0.9 + brighter glass).
 */
@Component
export struct MiloBackNode {
  onTap: () => void = () => {};
  @State pressed: boolean = false;
  @State pressScale: number = 1;

  private animatePress(isPressed: boolean): void {
    this.getUIContext().animateTo(
      { duration: 180, curve: curves.springMotion(0.38, 0.7) },
      () => {
        this.pressed = isPressed;
        this.pressScale = isPressed ? 0.9 : 1;
      },
    );
  }

  build() {
    Stack() {
      Path({ width: 38, height: 38 })
        .commands(`M${pathPx(25.5)} ${pathPx(11.5)} L${pathPx(14.5)} ${pathPx(19)} L${pathPx(25.5)} ${pathPx(26.5)}`)
        .fillOpacity(0)
        .stroke(INK_INTERACTIVE)
        .strokeWidth(3)
        .strokeLineCap(LineCapStyle.Round)
        .strokeLineJoin(LineJoinStyle.Round)
    }
    .width(38)
    .height(38)
    .borderRadius(19)
    .backgroundColor(this.pressed ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.11)')
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 1, color: 'rgba(255,255,255,0.14)' })
    .scale({ x: this.pressScale, y: this.pressScale })
    .onClick(() => this.onTap())
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.animatePress(true);
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.animatePress(false);
      }
    })
  }
}

/**
 * Global stage backdrop from `App.tsx`: deep indigo gradient, two blurred
 * aurora blobs and the seeded starfield, shared by every screen.
 */
@Component
export struct StageBackdrop {
  @State blobAX: number = 0;
  @State blobAY: number = 0;
  @State blobBX: number = 0;
  @State blobBY: number = 0;

  aboutToAppear(): void {
    // Aurora drift, mirroring the web `blob-float` keyframes.
    this.getUIContext().animateTo(
      {
        duration: 18000,
        curve: curves.cubicBezierCurve(0.45, 0, 0.55, 1),
        iterations: -1,
        playMode: PlayMode.Alternate,
      },
      () => {
        this.blobAX = 26;
        this.blobAY = 18;
      },
    );
    this.getUIContext().animateTo(
      {
        duration: 22000,
        curve: curves.cubicBezierCurve(0.45, 0, 0.55, 1),
        iterations: -1,
        playMode: PlayMode.AlternateReverse,
      },
      () => {
        this.blobBX = -22;
        this.blobBY = -16;
      },
    );
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({ angle: 180, colors: [['#0b0a1e', 0], ['#06060f', 0.7]] })

      Column()
        .width('130%')
        .height('42%')
        .borderRadius(999)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '60%',
          colors: [['rgba(139,124,246,0.32)', 0], ['rgba(126,232,250,0.10)', 0.45], ['rgba(126,232,250,0)', 1]],
        })
        .opacity(0.5)
        .position({ x: '-30%', y: '-14%' })
        .translate({ x: this.blobAX, y: this.blobAY })

      Column()
        .width('120%')
        .height('36%')
        .borderRadius(999)
        .radialGradient({
          center: ['50%', '50%'],
          radius: '60%',
          colors: [['rgba(240,166,202,0.28)', 0], ['rgba(255,217,160,0.08)', 0.45], ['rgba(255,217,160,0)', 1]],
        })
        .opacity(0.5)
        .position({ x: '-15%', y: '74%' })
        .translate({ x: this.blobBX, y: this.blobBY })

      Starfield({ count: 0, seed: 0x5a17c0fe, color: '#dcd6ff' })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }
}
