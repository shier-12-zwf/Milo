export interface VibrateTarget {
  vibrate?: (pattern: number | number[]) => boolean
}

export function triggerTapHaptic(
  target: VibrateTarget | undefined = typeof navigator === 'undefined' ? undefined : navigator,
): boolean {
  try {
    return target?.vibrate?.(10) ?? false
  } catch {
    return false
  }
}
