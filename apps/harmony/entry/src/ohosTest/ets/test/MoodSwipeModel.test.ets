import { describe, expect, it } from '@ohos/hypium';
import {
  activeMoodIndex,
  ECHO_MOOD_MAX_FLING_STEPS,
  ECHO_MOOD_PROJECTION_MS,
  ECHO_MOOD_ROTARY_LOCK_PX,
  moodOrbitTextPose,
  moodPointerAngle,
  moodPositionFromRotation,
  moodRotationTravelPx,
  moodTickAngle,
  moodTickOpacity,
  nearestMoodPosition,
  orbitalMoodPose,
  projectMoodSnap,
  shortestMoodAngleDelta,
  type MoodOrbitTextPose,
  wrapMoodIndex,
} from '../../../main/ets/features/mood/MoodSwipeModel';

function moodSwipeModelSuite() {
  describe('moodSwipeModelTest', () => {
    it('keeps the active tick at the lower focus point and orbits neighbors around it', 0, () => {
      expect(moodTickAngle(3, 3, 15)).assertEqual(180);
      expect(moodTickAngle(4, 3, 15)).assertEqual(204);
      expect(moodTickAngle(2, 3, 15)).assertEqual(156);
      expect(moodTickOpacity(3, 3, 15)).assertEqual(1);
      expect(moodTickOpacity(4, 3, 15)).assertEqual(0.7);
      expect(moodTickOpacity(10, 3, 15)).assertEqual(0.22);
    });

    it('rotates every tick as one rigid dial with fixed spacing', 0, () => {
      const from = 3;
      const to = nearestMoodPosition(from, 12, 15);
      const rotations: number[] = [];
      for (let index = 0; index < 15; index += 1) {
        rotations.push(moodTickAngle(index, to, 15) - moodTickAngle(index, from, 15));
      }
      const unique = new Set<number>();
      for (let index = 0; index < rotations.length; index += 1) {
        unique.add(rotations[index]);
      }
      expect(unique.size).assertEqual(1);
      expect(rotations[0]).assertEqual(144);

      for (let index = 0; index < 14; index += 1) {
        const diff = moodTickAngle(index + 1, to, 15) - moodTickAngle(index, to, 15);
        expect(diff).assertEqual(24);
      }
    });

    it('collapsed orbit text exposes only the active mood', 0, () => {
      const active = moodOrbitTextPose(3, 3, 15, false);
      const neighbor = moodOrbitTextPose(4, 3, 15, false);
      expect(active.visible).assertEqual(true);
      expect(active.opacity).assertEqual(1);
      expect(active.angle).assertEqual(180);
      expect(neighbor.visible).assertEqual(false);
      expect(neighbor.opacity).assertEqual(0);
    });

    it('expanded orbit text reveals all fifteen moods with a clear focus', 0, () => {
      const poses: MoodOrbitTextPose[] = [];
      for (let index = 0; index < 15; index += 1) {
        poses.push(moodOrbitTextPose(index, 3, 15, true));
      }
      let visibleCount = 0;
      for (let index = 0; index < poses.length; index += 1) {
        if (poses[index].visible) {
          visibleCount += 1;
        }
      }
      expect(visibleCount).assertEqual(15);
      expect(poses[3].opacity).assertEqual(1);
      expect(poses[4].opacity).assertEqual(0.56);
      expect(poses[10].opacity).assertEqual(0.56);
      expect(poses[3].scale > poses[4].scale).assertTrue();
    });

    it('blends the outgoing and incoming label while dragging', 0, () => {
      const outgoing = moodOrbitTextPose(3, 3.4, 15, true);
      const incoming = moodOrbitTextPose(4, 3.4, 15, true);
      expect(outgoing.opacity > incoming.opacity).assertTrue();
      expect(outgoing.opacity < 1).assertTrue();
      expect(incoming.opacity > 0.56).assertTrue();
    });

    it('wraps and activates at the nearest half-step', 0, () => {
      expect(wrapMoodIndex(-1, 15)).assertEqual(14);
      expect(wrapMoodIndex(15, 15)).assertEqual(0);
      expect(activeMoodIndex(3.49, 15)).assertEqual(3);
      expect(activeMoodIndex(3.51, 15)).assertEqual(4);
    });

    it('maps pointer angle clockwise from the dial center', 0, () => {
      expect(moodPointerAngle(110, 100, 100, 100)).assertEqual(0);
      expect(moodPointerAngle(100, 110, 100, 100)).assertEqual(90);
      expect(moodPointerAngle(90, 100, 100, 100)).assertEqual(180);
      expect(moodPointerAngle(100, 90, 100, 100)).assertEqual(-90);
    });

    it('unwraps angle deltas across the ±180° seam', 0, () => {
      const angles: number[] = [170, 179, -179, -160];
      const rotation = angles[1] - angles[0] + shortestMoodAngleDelta(angles[1], angles[2]) + shortestMoodAngleDelta(angles[2], angles[3]);
      expect(rotation).assertEqual(30);
    });

    it('exposes the constants used by the gesture model', 0, () => {
      expect(ECHO_MOOD_ROTARY_LOCK_PX).assertEqual(6);
      expect(ECHO_MOOD_PROJECTION_MS).assertEqual(140);
      expect(ECHO_MOOD_MAX_FLING_STEPS).assertEqual(2);
    });

    it('computes continuous position from rotation', 0, () => {
      expect(moodPositionFromRotation(0, 24, 15)).assertEqual(-1);
      expect(moodPositionFromRotation(0, 360, 15)).assertEqual(-15);
    });

    it('measures arc length in pixels from rotation and radius', 0, () => {
      expect(moodRotationTravelPx(0, 100)).assertEqual(0);
      expect(moodRotationTravelPx(360, 100) > 627 && moodRotationTravelPx(360, 100) < 629).assertTrue();
    });

    it('projects a fling and clamps to max steps', 0, () => {
      // 0.05 steps/ms * 140 ms = 7 steps → clamped to +2
      expect(projectMoodSnap(3, 0.05)).assertEqual(3 + 2);
      expect(projectMoodSnap(3, 0.5)).assertEqual(3 + 2);
      expect(projectMoodSnap(3, -0.5)).assertEqual(3 - 2);
    });

    it('orbitalMoodPose renders only the active mood', 0, () => {
      const active = orbitalMoodPose(3, 3, 15);
      const neighbor = orbitalMoodPose(4, 3, 15);
      expect(active.visible).assertEqual(true);
      expect(active.opacity).assertEqual(1);
      expect(active.zIndex).assertEqual(30);
      expect(neighbor.visible).assertEqual(false);
      expect(neighbor.opacity).assertEqual(0);
    });
  });
}

export default function moodSwipeModelTest() {
  moodSwipeModelSuite();
}
