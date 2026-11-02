import {
  getMoodAsset,
  moodAssetSheetLeftPercent,
  type MoodAsset,
  type MoodAssetSheetName,
  MOOD_SHEET_HEIGHT,
  MOOD_SHEET_PANEL_COUNT,
  MOOD_SHEET_WIDTH,
} from '../../core/model/MoodAssets';
import { MOODS, type MoodId } from '../../core/model/Moods';

@Component
export struct MoodPlanet {
  @Prop moodId: MoodId = 'calm';
  @Prop planetSize: number = 120;

  private asset(): MoodAsset | undefined {
    return getMoodAsset(this.moodId);
  }

  private sheet(): MoodAssetSheetName | undefined {
    const asset = this.asset();
    if (asset === undefined) {
      return undefined;
    }
    return asset.sheet;
  }

  private panelViewportHeight(): number {
    return this.planetSize * (MOOD_SHEET_HEIGHT / MOOD_SHEET_WIDTH);
  }

  private innerImageWidth(): number {
    return this.planetSize * MOOD_SHEET_PANEL_COUNT;
  }

  private innerImageHeight(): number {
    return this.panelViewportHeight();
  }

  private offsetX(): number {
    const asset = this.asset();
    if (asset === undefined) {
      return 0;
    }
    return (moodAssetSheetLeftPercent(asset) / 100) * this.planetSize;
  }

  private label(): string {
    for (let index = 0; index < MOODS.length; index += 1) {
      const mood = MOODS[index];
      if (mood.id === this.moodId && mood.labels.length > 0) {
        return mood.labels[0];
      }
    }
    return this.moodId;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.sheet() !== undefined) {
        if (this.sheet() === 'mood_sheet_01') {
          Image($r('app.media.mood_sheet_01'))
            .width(this.innerImageWidth())
            .height(this.innerImageHeight())
            .offset({ x: this.offsetX(), y: 0 })
            .interpolation(ImageInterpolation.High)
            .objectFit(ImageFit.Fill)
            .draggable(false)
        } else if (this.sheet() === 'mood_sheet_02') {
          Image($r('app.media.mood_sheet_02'))
            .width(this.innerImageWidth())
            .height(this.innerImageHeight())
            .offset({ x: this.offsetX(), y: 0 })
            .interpolation(ImageInterpolation.High)
            .objectFit(ImageFit.Fill)
            .draggable(false)
        } else if (this.sheet() === 'mood_sheet_03') {
          Image($r('app.media.mood_sheet_03'))
            .width(this.innerImageWidth())
            .height(this.innerImageHeight())
            .offset({ x: this.offsetX(), y: 0 })
            .interpolation(ImageInterpolation.High)
            .objectFit(ImageFit.Fill)
            .draggable(false)
        } else if (this.sheet() === 'mood_sheet_04') {
          Image($r('app.media.mood_sheet_04'))
            .width(this.innerImageWidth())
            .height(this.innerImageHeight())
            .offset({ x: this.offsetX(), y: 0 })
            .interpolation(ImageInterpolation.High)
            .objectFit(ImageFit.Fill)
            .draggable(false)
        } else {
          Image($r('app.media.mood_sheet_05'))
            .width(this.innerImageWidth())
            .height(this.innerImageHeight())
            .offset({ x: this.offsetX(), y: 0 })
            .interpolation(ImageInterpolation.High)
            .objectFit(ImageFit.Fill)
            .draggable(false)
        }
      }
    }
    .width(this.planetSize)
    .height(this.panelViewportHeight())
    .clip(true)
    .accessibilityText(this.label() + '情绪星球')
  }
}