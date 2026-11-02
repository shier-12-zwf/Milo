export const BLACK_HOLE_VERTEX_SHADER = `
attribute vec2 aPosition;
varying vec2 vUv;

void main() {
  vUv = aPosition * 0.5 + 0.5;
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`

export const BLACK_HOLE_FRAGMENT_SHADER = `
precision highp float;

varying vec2 vUv;
uniform vec2 uResolution;
uniform float uTime;
uniform vec2 uPointer;
uniform float uPointerActive;
uniform float uStarSpeed;
uniform float uDensity;
uniform float uHueShift;
uniform float uSpeed;
uniform float uGlowIntensity;
uniform float uSaturation;
uniform float uRepulsionStrength;
uniform float uTwinkleIntensity;
uniform float uRotationSpeed;

const float STAR_SIZE_GAIN = 1.65;
const float POINTER_REPULSION_SCALE = 0.055;
const float MICRO_DUST_POPULATION = 0.16;
const float FINE_STAR_POPULATION = 0.079;
const float MID_STAR_POPULATION = 0.056;
const float STARFIELD_DENSITY_FLOOR = 0.52;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
    mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x),
    f.y
  );
}

float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.55;
  for (int octave = 0; octave < 5; octave++) {
    value += noise2(p) * amplitude;
    p = p * 2.03 + vec2(17.2, 9.4);
    amplitude *= 0.5;
  }
  return value;
}

mat2 rotate2d(float angle) {
  float s = sin(angle);
  float c = cos(angle);
  return mat2(c, -s, s, c);
}

vec3 hueColor(float hue) {
  return 0.5 + 0.5 * cos(6.2831853 * (hue + vec3(0.0, 0.333, 0.667)));
}

vec2 repelPointer(vec2 uv, vec2 pointer) {
  vec2 delta = uv - pointer;
  float distanceToPointer = max(length(delta), 0.025);
  float influence = exp(-distanceToPointer * 8.0) * uPointerActive;
  return uv + normalize(delta) * influence * uRepulsionStrength * POINTER_REPULSION_SCALE;
}

float starLayer(
  vec2 uv,
  float scale,
  float layerSeed,
  float population,
  vec2 radiusRange
) {
  vec2 grid = uv * scale + layerSeed;
  vec2 cell = floor(grid);
  vec2 local = fract(grid) - 0.5;
  float seed = hash21(cell + layerSeed);
  vec2 offset = vec2(seed, hash21(cell + 7.31)) - 0.5;
  float driftTime = uTime * uSpeed;
  vec2 stellarDrift = vec2(
    sin(driftTime * (0.12 + seed * 0.05) + seed * 19.2),
    cos(driftTime * (0.10 + seed * 0.04) + seed * 23.7)
  ) * 0.018;
  float distanceToStar = length(local - offset * 0.58 - stellarDrift);
  float radius = mix(radiusRange.x, radiusRange.y, seed) * STAR_SIZE_GAIN;
  float starCore = 1.0 - smoothstep(radius * 0.24, radius * 0.78, distanceToStar);
  float starHalo = 1.0 - smoothstep(radius * 0.62, radius * 2.25, distanceToStar);
  float star = starCore + starHalo * 0.22;
  float threshold = 1.0 - clamp(population * uDensity, 0.0, 0.62);
  float twinkle = 1.0 + sin(uTime * (1.15 + seed * 2.6) + seed * 40.0) * uTwinkleIntensity;
  return star * step(threshold, seed) * twinkle;
}

float galaxyDepth(float phase) {
  return fract(phase + uTime * uStarSpeed * uSpeed * 0.022);
}

float galaxyDepthFade(float depth) {
  float fadeIn = smoothstep(0.0, 0.14, depth);
  float fadeOut = 1.0 - smoothstep(0.82, 1.0, depth);
  return fadeIn * fadeOut;
}

float animatedStarLayer(
  vec2 uv,
  float scale,
  float layerSeed,
  float population,
  vec2 radiusRange,
  float phase
) {
  float depth = galaxyDepth(phase);
  float zoom = mix(0.84, 1.24, depth);
  float depthGain = mix(0.72, 1.18, depth) * galaxyDepthFade(depth);
  vec2 layerDrift = vec2(
    sin(uTime * uSpeed * 0.055 + layerSeed),
    cos(uTime * uSpeed * 0.043 + layerSeed * 1.37)
  ) * 0.006;
  return starLayer(uv * zoom + layerDrift, scale, layerSeed, population, radiusRange) * depthGain;
}

float microStarDust(vec2 uv) {
  float dust = animatedStarLayer(
    uv + vec2(-0.19, 0.27),
    420.0,
    73.6,
    MICRO_DUST_POPULATION,
    vec2(0.20, 0.38),
    0.0
  ) * 0.20;
  dust += animatedStarLayer(
    uv + vec2(0.37, -0.16),
    332.0,
    91.8,
    MICRO_DUST_POPULATION * 0.82,
    vec2(0.18, 0.34),
    0.5
  ) * 0.24;
  return dust;
}

float layeredStarField(vec2 uv) {
  float clusterA = smoothstep(0.28, 0.74, fbm(uv * 1.72 + vec2(8.4, -3.7)));
  float clusterB = smoothstep(
    0.40,
    0.76,
    fbm(rotate2d(-0.34) * uv * 3.15 + vec2(-4.8, 11.2))
  );
  float densityFloor = STARFIELD_DENSITY_FLOOR;
  float cluster = densityFloor + clusterA * 0.54 + clusterB * 0.31;

  float stars = microStarDust(uv) * mix(0.78, 1.22, clusterB);
  stars += animatedStarLayer(
    uv,
    214.0,
    41.2,
    FINE_STAR_POPULATION,
    vec2(0.13, 0.27),
    0.1667
  ) * 0.25;
  stars += animatedStarLayer(
    uv + vec2(0.13, -0.21),
    132.0,
    19.4,
    MID_STAR_POPULATION,
    vec2(0.10, 0.23),
    0.3333
  ) * 0.42;
  stars += animatedStarLayer(
    uv - vec2(0.31, 0.07),
    72.0,
    7.7,
    0.038,
    vec2(0.07, 0.18),
    0.6667
  ) * 0.72;
  stars += animatedStarLayer(
    uv + vec2(0.08, 0.11),
    34.0,
    2.7,
    0.010,
    vec2(0.045, 0.12),
    0.8333
  ) * 1.24;
  return stars * cluster;
}

void main() {
  float aspect = uResolution.x / max(uResolution.y, 1.0);
  vec2 scale = vec2(aspect, 1.0);
  vec2 uv = (vUv * 2.0 - 1.0) * scale;
  vec2 pointer = (uPointer * 2.0 - 1.0) * scale;
  float starRotation = uTime * uRotationSpeed * 0.18;
  vec2 starUv = rotate2d(starRotation) * uv;
  float stars = layeredStarField(repelPointer(starUv, pointer));

  vec3 coldTint = hueColor(fract(uHueShift / 360.0));
  vec3 silver = mix(vec3(0.82, 0.85, 0.91), coldTint, uSaturation * 0.08);
  vec3 color = silver * stars * (0.82 + uGlowIntensity * 0.88);

  float alpha = clamp(max(max(color.r, color.g), color.b) * 1.38, 0.0, 1.0);
  gl_FragColor = vec4(color, alpha);
}
`
