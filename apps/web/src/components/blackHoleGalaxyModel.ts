export interface BlackHoleGalaxySettings {
  starSpeed: number
  density: number
  hueShift: number
  speed: number
  glowIntensity: number
  saturation: number
  mouseRepulsion: boolean
  repulsionStrength: number
  twinkleIntensity: number
  rotationSpeed: number
  transparent: boolean
}

export const BLACK_HOLE_GALAXY_SETTINGS: BlackHoleGalaxySettings = {
  starSpeed: 0.7,
  density: 1.7,
  hueShift: 140,
  speed: 1.4,
  glowIntensity: 0.45,
  saturation: 0.15,
  mouseRepulsion: true,
  repulsionStrength: 2,
  twinkleIntensity: 0.4,
  rotationSpeed: 0.1,
  transparent: true,
}

export function isBlackHoleGalaxyDemo(search: string): boolean {
  const backgroundDemo = new URLSearchParams(search).get('bgDemo')
  return backgroundDemo === null || backgroundDemo === 'black-hole'
}

export function capBackgroundDpr(dpr: number): number {
  return Math.max(1, Math.min(1.5, dpr))
}

export function normalizePointer(
  clientX: number,
  clientY: number,
  rect: Pick<DOMRect, 'left' | 'top' | 'width' | 'height'>,
): [number, number] {
  return [
    Math.max(0, Math.min(1, (clientX - rect.left) / rect.width)),
    Math.max(0, Math.min(1, 1 - (clientY - rect.top) / rect.height)),
  ]
}
