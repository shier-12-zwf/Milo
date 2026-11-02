/**
 * Three-dot "typing" indicator, a 1:1 port of the Web `.typing-dots`
 * animation (dot-pulse, 1.2s cycle, 0.15s stagger, -3px lift).
 */
@Component
export struct TypingDots {
  @State dotOpacity: number[] = [0.25, 0.25, 0.25];
  @State dotOffset: number[] = [0, 0, 0];

  build() {
    Row({ space: 5 }) {
      ForEach([0, 1, 2], (index: number) => {
        Circle({ width: 6, height: 6 })
          .fill('rgba(234,230,255,0.72)')
          .opacity(this.dotOpacity[index])
          .translate({ y: this.dotOffset[index] })
      }, (index: number) => `${index}`)
    }
    .padding({ top: 4, bottom: 4, left: 2, right: 2 })
    .onAppear(() => {
      for (let index = 0; index < 3; index += 1) {
        this.getUIContext().animateTo(
          {
            duration: 600,
            curve: Curve.EaseInOut,
            iterations: -1,
            playMode: PlayMode.Alternate,
            delay: index * 150,
          },
          () => {
            this.dotOpacity[index] = 1;
            this.dotOffset[index] = -3;
          },
        );
      }
    })
  }
}
