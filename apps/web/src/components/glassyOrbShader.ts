export const VERTEX_SHADER = `
attribute vec2 aPosition;
varying vec2 vUv;

void main() {
  vUv = aPosition * 0.5 + 0.5;
  gl_Position = vec4(aPosition, 0.0, 1.0);
}
`

export const FRAGMENT_SHADER = `
precision highp float;

varying vec2 vUv;
uniform vec2 uResolution;
uniform float uTime;
uniform float uSpin;
uniform float uPulse;
uniform vec3 uColorMain;
uniform vec3 uColorDeep;
uniform vec3 uColorLight;
uniform float uSilverTone;
uniform vec2 uNebulaFlow;
uniform float uStarDensity;
uniform float uLightBias;
uniform float uTurbulence;
uniform float uMoodPulse;
const float STAR_RADIUS = 0.072;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
  return vec2(hash21(p + vec2(17.7, 3.1)), hash21(p + vec2(4.9, 31.6)));
}

float hash31(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.yzx + 33.33);
  return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
  vec3 cell = floor(p);
  vec3 local = fract(p);
  local = local * local * (3.0 - 2.0 * local);
  float n000 = hash31(cell);
  float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
  float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
  float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
  float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
  float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
  float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
  float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));
  return mix(
    mix(mix(n000, n100, local.x), mix(n010, n110, local.x), local.y),
    mix(mix(n001, n101, local.x), mix(n011, n111, local.x), local.y),
    local.z
  );
}

float fbm(vec3 p) {
  float value = 0.0;
  float weight = 0.55;
  for (int octave = 0; octave < 5; octave++) {
    value += weight * noise3(p);
    p = p * 2.03 + vec3(17.1, 9.2, 13.7);
    weight *= 0.5;
  }
  return value;
}

float nebulaDensity(vec3 point) {
  vec2 flow = uNebulaFlow * uTime * 0.06;
  float cloud = fbm(point * (2.15 + uTurbulence * 0.42) + vec3(flow, uTime * 0.018));
  float folded = abs(point.y - uLightBias * 0.42 + (0.14 + uTurbulence * 0.14) * sin(point.x * 4.0 + uTime * 0.24));
  float band = exp(-folded * 6.2) * (1.0 - smoothstep(0.08, 1.15, length(point.xy)));
  return smoothstep(0.34, 0.8, cloud) * 0.7 + band;
}

float starLayer(vec2 uv, float scale, float threshold) {
  vec2 cell = floor(uv * scale);
  vec2 local = fract(uv * scale) - 0.5;
  float seed = hash21(cell);
  vec2 offset = vec2(seed, hash21(cell + 19.73)) - 0.5;
  float distanceToStar = length(local - offset * 0.64);
  float star = (1.0 - smoothstep(0.0, STAR_RADIUS, distanceToStar)) * step(threshold, seed);
  return star * (0.5 + 1.4 * hash21(cell + 4.1));
}

float stellarDust(vec2 uv) {
  float densityBias = (uStarDensity - 1.0) * 0.055;
  float dust = starLayer(uv, 38.0, 0.70 - densityBias);
  dust += starLayer(uv + vec2(11.7, 7.3), 76.0, 0.90 - densityBias * 0.55) * 0.72;
  dust += starLayer(uv - vec2(5.1, 13.9), 118.0, 0.97 - densityBias * 0.24) * 0.48;
  return dust * (0.62 + uStarDensity * 0.38);
}

float cellularVeins(vec2 uv) {
  vec2 cell = floor(uv);
  vec2 local = fract(uv);
  float nearest = 8.0;
  float secondNearest = 8.0;

  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      vec2 neighbor = vec2(float(x), float(y));
      vec2 feature = neighbor + hash22(cell + neighbor);
      float distanceToFeature = length(feature - local);
      if (distanceToFeature < nearest) {
        secondNearest = nearest;
        nearest = distanceToFeature;
      } else if (distanceToFeature < secondNearest) {
        secondNearest = distanceToFeature;
      }
    }
  }

  return 1.0 - smoothstep(0.018, 0.095, secondNearest - nearest);
}

float cloudBoundary(vec2 point) {
  vec2 flow = uNebulaFlow * uTime * 0.025;
  float cloud = fbm(vec3(point * vec2(3.3, 4.1) + flow, uTime * 0.022));
  float sphereArc = pow(abs(point.x), 1.7) * 0.28;
  return -0.52 + sphereArc + uLightBias * 0.18 + (cloud - 0.5) * (0.28 + uTurbulence * 0.08);
}

float cloudShelf(vec2 point) {
  float boundary = cloudBoundary(point);
  return 1.0 - smoothstep(boundary, boundary + 0.16, point.y);
}

float cloudRim(vec2 point) {
  vec2 flow = uNebulaFlow * uTime * 0.025;
  float cloud = fbm(vec3(point * vec2(3.3, 4.1) + flow, uTime * 0.022));
  float boundary = cloudBoundary(point);
  return exp(-abs(point.y - boundary) * 19.0) * (0.72 + cloud * 0.42);
}

mat2 rotation(float angle) {
  float sine = sin(angle);
  float cosine = cos(angle);
  return mat2(cosine, -sine, sine, cosine);
}

float galaxyCore(vec2 point) {
  return exp(-72.0 * dot(point, point));
}

void main() {
  vec2 aspect = vec2(uResolution.x / max(uResolution.y, 1.0), 1.0);
  vec2 p = (vUv * 2.0 - 1.0) * aspect / 0.92;
  float radiusSquared = dot(p, p);
  float edgeAlpha = 1.0 - smoothstep(0.94, 1.0, radiusSquared);
  if (edgeAlpha <= 0.001) discard;

  float z = sqrt(max(0.0, 1.0 - radiusSquared));
  vec3 normal = normalize(vec3(p, z));
  vec3 rotated = normal;
  rotated.xy = rotation(uSpin + uTime * 0.075) * rotated.xy;
  rotated.yz = rotation(-0.22 + sin(uTime * 0.09) * 0.08) * rotated.yz;

  float density = nebulaDensity(rotated);
  vec2 corePoint = rotated.xy - vec2(-0.12, 0.04 + uLightBias);
  float core = galaxyCore(corePoint);
  vec2 starUv = rotated.xy / max(0.28, 0.42 + rotated.z);
  float stars = stellarDust(starUv + uTime * 0.0008);
  float veins = cellularVeins(starUv * 5.4 + uNebulaFlow * uTime * 0.004);
  float shelf = cloudShelf(p);
  float shelfRim = cloudRim(p);

  vec3 cosmicMain = mix(uColorMain, uColorLight, 0.24);
  vec3 cosmicDeep = mix(uColorDeep, uColorMain * 0.64, 0.28);
  vec3 cosmicLight = mix(uColorLight, vec3(1.0), 0.38);
  vec3 silverMain = mix(vec3(0.40, 0.42, 0.47), uColorMain, 0.16);
  vec3 silverDeep = mix(vec3(0.075, 0.085, 0.11), uColorDeep, 0.12);
  vec3 silverLight = mix(vec3(0.72, 0.75, 0.82), uColorLight, 0.18);
  cosmicMain = mix(cosmicMain, silverMain, uSilverTone);
  cosmicDeep = mix(cosmicDeep, silverDeep, uSilverTone);
  cosmicLight = mix(cosmicLight, silverLight, uSilverTone);

  vec3 color = mix(cosmicDeep, cosmicMain, 0.46 + z * 0.28) * (0.32 + z * 0.24);
  color += cosmicMain * (0.05 + density * 0.36);
  color += cosmicLight * (core * 0.28 + stars * 1.18);
  color += cosmicLight * veins * (0.022 + density * 0.032 + shelfRim * 0.05);
  color += cosmicMain * (shelf * 0.10 + shelfRim * 0.34);
  color += cosmicLight * (shelf * 0.025 + shelfRim * 0.28);
  color += cosmicLight * uPulse * (0.08 + core * 0.18);
  float moodBreath = 0.5 + 0.5 * sin(uTime * (0.55 + uMoodPulse));
  color += cosmicLight * uMoodPulse * moodBreath * (0.035 + core * 0.08);

  float fresnel = pow(1.0 - z, 3.1);
  float rimAngle = atan(p.y, p.x);
  float fracture = pow(max(0.0, sin(rimAngle * 13.0 + fbm(normal * 5.0) * 8.0)), 18.0);
  vec3 prism = 0.5 + 0.5 * cos(6.2831853 * (vec3(0.02, 0.35, 0.68) + rimAngle * 0.18));
  vec3 silverPrism = mix(vec3(dot(prism, vec3(0.299, 0.587, 0.114))), vec3(0.70, 0.73, 0.82), 0.32);
  prism = mix(prism, silverPrism, uSilverTone * 0.92);
  color += prism * fracture * fresnel * 1.15;

  vec3 lightDirection = normalize(vec3(-0.48, 0.62, 0.62));
  float specular = pow(max(dot(normal, lightDirection), 0.0), 54.0);
  float softReflection = pow(max(dot(normal, normalize(vec3(-0.62, 0.34, 0.71))), 0.0), 8.0);
  color += vec3(1.0, 0.98, 1.0) * specular * 0.82;
  color += cosmicLight * softReflection * 0.12;
  color += mix(cosmicMain, cosmicLight, 0.64) * fresnel * 0.48;
  color *= 0.91 + z * 0.14;

  gl_FragColor = vec4(color, edgeAlpha);
}
`
