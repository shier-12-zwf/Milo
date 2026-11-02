/** ArkUI fingerList is indexed by pointer id and can contain empty slots. */
export interface GesturePoint {
  x: number;
  y: number;
}

function firstPoint(fingers: Array<FingerInfo | undefined | null> | undefined): GesturePoint | null {
  if (!fingers) return null;
  for (let index = 0; index < fingers.length; index += 1) {
    const finger = fingers[index];
    if (finger && Number.isFinite(finger.localX) && Number.isFinite(finger.localY)) {
      return { x: finger.localX, y: finger.localY };
    }
  }
  return null;
}

export function gestureLocalPoint(event: GestureEvent | undefined): GesturePoint | null {
  if (!event) return null;
  return firstPoint(event.fingerInfos) ?? firstPoint(event.fingerList);
}
