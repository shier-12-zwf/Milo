import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const home = readFileSync(new URL('../src/pages/Home.tsx', import.meta.url), 'utf8')
const css = readFileSync(new URL('../src/index.css', import.meta.url), 'utf8')
const carouselUrl = new URL('../src/components/MoodOrbitCarousel.tsx', import.meta.url)
const moodSwipeUrl = new URL('../src/lib/useMoodSwipe.ts', import.meta.url)

test('the first mood step omits the old question heading', () => {
  assert.doesNotMatch(home, /此刻，你的心里泛起了什么？/)
  assert.doesNotMatch(css, /\.echo-feel-title/)
})

test('echo mode uses the original raster orbit on both chooser steps', () => {
  assert.match(home, /import \{ MoodOrbitCarousel \}/)
  assert.match(home, /import \{ MoodPlanetImage \}/)
  assert.match(home, /<MoodOrbitCarousel/)
  assert.match(home, /<MoodPlanetImage[\s\S]*moodId=\{echoMood\.id\}/)
})

test('the orbit exposes the seven level-selector mood controls', async () => {
  const { readFile } = await import('node:fs/promises')
  const carousel = await readFile(carouselUrl, 'utf8')

  assert.match(carousel, /ECHO_SELECTOR_MOODS\.map/)
  assert.match(carousel, /className="mood-orbit-step"/)
  assert.match(carousel, /className="mood-orbit-text"/)
  assert.match(carousel, /aria-label=\{`选择\$\{mood\.label\}`\}/)
  assert.match(carousel, /aria-pressed=\{index === activeIndex\}/)
  assert.match(carousel, /onClick=\{\(\) => selectMood\(index\)\}/)
  assert.match(carousel, /const ORB_VIEWPORT_SIZE = 244/)
})

test('the orbit renders only the active mood artwork', async () => {
  const { readFile } = await import('node:fs/promises')
  const carousel = await readFile(carouselUrl, 'utf8')

  assert.match(carousel, /const activeMood = ECHO_SELECTOR_MOODS\[activeIndex\]/)
  assert.match(carousel, /<MoodPlanetImage moodId=\{activeMood\.id\}/)
})

test('the complete mood vocabulary is visible on first render', () => {
  assert.match(home, /const \[orbitExpanded, setOrbitExpanded\] = useState\(true\)/)
  assert.match(home, /expanded=\{orbitExpanded\}/)
  assert.match(home, /onExpandedChange=\{setOrbitExpanded\}/)
  assert.match(home, /沿圆环旋转，或点击任意情绪直接切换/)
  assert.doesNotMatch(home, /点击或按住圆环，显示全部情绪/)
})

test('pressing the active planet immediately reveals the text-only orbit without arrows', async () => {
  const { readFile } = await import('node:fs/promises')
  const carousel = await readFile(carouselUrl, 'utf8')

  assert.match(carousel, /expanded: boolean/)
  assert.match(carousel, /onExpandedChange: \(expanded: boolean\) => void/)
  assert.match(carousel, /className="mood-orbit-toggle"/)
  assert.match(carousel, /aria-expanded=\{expanded\}/)
  assert.match(carousel, /onPointerDown=\{revealOrbit\}/)
  assert.match(carousel, /className="mood-orbit-texts"/)
  assert.match(carousel, /moodOrbitTextPose/)
  assert.match(carousel, /moodTickAngle/)
  assert.match(carousel, /moodTickOpacity/)
  assert.doesNotMatch(home, /<span aria-hidden="true">[‹›]<\/span>/)
})

test('the complete mood dial is one continuous drag surface', async () => {
  const { readFile } = await import('node:fs/promises')
  const [carousel, moodSwipe] = await Promise.all([
    readFile(carouselUrl, 'utf8'),
    readFile(moodSwipeUrl, 'utf8'),
  ])

  assert.match(home, /data-mood-drag-surface=\{echoVoid \? true : undefined\}/)
  assert.match(carousel, /data-mood-drag-surface="true"/)
  assert.doesNotMatch(carousel, /stopDrag/)
  assert.doesNotMatch(carousel, /onPointerDown=\{stopDrag\}/)
  assert.match(moodSwipe, /const captureOptions = \{ capture: true \} as const/)
  assert.match(moodSwipe, /addEventListener\('pointerdown', down, captureOptions\)/)
  assert.match(moodSwipe, /addEventListener\('click', suppressDraggedClick, captureOptions\)/)
})

test('the dial follows circular pointer angles and captures only after rotary lock', async () => {
  const { readFile } = await import('node:fs/promises')
  const moodSwipe = await readFile(moodSwipeUrl, 'utf8')
  const downBlock = moodSwipe.slice(
    moodSwipe.indexOf('const down ='),
    moodSwipe.indexOf('const track ='),
  )
  const trackBlock = moodSwipe.slice(
    moodSwipe.indexOf('const track ='),
    moodSwipe.indexOf('const finish ='),
  )

  assert.doesNotMatch(downBlock, /setPointerCapture/)
  assert.match(trackBlock, /moodPointerAngle/)
  assert.match(trackBlock, /shortestMoodAngleDelta/)
  assert.match(trackBlock, /moodRotationTravelPx/)
  assert.match(trackBlock, /setPointerCapture/)
  assert.match(trackBlock, /getCoalescedEvents/)
  assert.match(moodSwipe, /window\.addEventListener\('pointermove', move\)/)
  assert.match(moodSwipe, /window\.addEventListener\('pointerup', up\)/)
})

test('release uses a recent angular velocity window for projection and snapping', async () => {
  const { readFile } = await import('node:fs/promises')
  const moodSwipe = await readFile(moodSwipeUrl, 'utf8')

  assert.match(moodSwipe, /const VELOCITY_WINDOW_MS = 100/)
  assert.match(moodSwipe, /rotationVelocity/)
  assert.match(moodSwipe, /positionVelocity/)
  assert.match(moodSwipe, /projectMoodSnap\(livePosition, positionVelocity\)/)
})

test('dragging visibly energizes the planet and rigid tick ring', () => {
  assert.match(css, /@keyframes echo-mood-impact/)
  assert.match(
    css,
    /\.mood-orbit-item > span\s*\{[^}]*animation:\s*echo-mood-impact/s,
  )
  assert.match(
    css,
    /\.mood-orbit-carousel\.is-dragging \.mood-orbit-steps::before\s*\{[^}]*transform:\s*scale\(1\.025\)/s,
  )
})

test('every revealed mood word is a directly selectable button', async () => {
  const { readFile } = await import('node:fs/promises')
  const carousel = await readFile(carouselUrl, 'utf8')

  assert.match(carousel, /<button[\s\S]*className="mood-orbit-text"[\s\S]*aria-pressed=\{index === activeIndex\}/)
  assert.match(carousel, /aria-hidden=\{!textPose\.visible\}/)
  assert.match(carousel, /tabIndex=\{textPose\.visible \? 0 : -1\}/)
  assert.match(carousel, /onClick=\{\(\) => selectMood\(index\)\}/)
  assert.match(carousel, /const selectMood = \(index: number\) => \{\s*onExpandedChange\(true\)\s*onSelect\(index\)/s)
})

test('keyboard focus follows the circular mood dial instead of drawing a square browser outline', () => {
  assert.match(css, /\.echo-feel-dial:focus-visible\s*\{[^}]*outline:\s*none/s)
  assert.match(css, /\.echo-feel-dial:focus-visible \.mood-orbit-steps::before\s*\{[^}]*border-color:[^}]*box-shadow:/s)
})

test('echo mode removes the abrupt bounce transition contract', () => {
  const combined = `${home}\n${css}`
  for (const forbidden of [
    'echo-orb-drop',
    'echo-orb-bounce',
    'ECHO_MOOD_IMPACT_MS',
    'ECHO_MOOD_BOUNCE_MS',
    'MoodPeek',
  ]) {
    assert.doesNotMatch(combined, new RegExp(forbidden))
  }
  assert.match(css, /520ms cubic-bezier\(0\.22, 0\.72, 0\.18, 1\)/)
})

test('mobile scrolling stays vertical and the single-orb lane does not widen the page', () => {
  assert.match(css, /\.screen-scroll\s*\{[^}]*overflow-x:\s*hidden;[^}]*overscroll-behavior-x:\s*none;/s)
  assert.match(css, /\.mood-orbit-lane\s*\{[^}]*inset:\s*-120px 0;/s)
})

test('the echo confirmation reads as transparent dark glass over the starfield', () => {
  assert.match(
    css,
    /\.screen--echo-void \.echo-confirm\s*\{[^}]*align-self:\s*center;[^}]*width:\s*min\(52vw, 260px\);[^}]*border-color:\s*rgba\(222, 229, 242, 0\.38\);[^}]*background:\s*rgba\(12, 15, 23, 0\.3\);[^}]*backdrop-filter:\s*blur\(30px\) saturate\(165%\) brightness\(82%\);/s,
  )
  assert.match(
    css,
    /\.screen--echo-void \.echo-confirm\s*\{[^}]*box-shadow:[^}]*inset 0 1px 0 rgba\(255, 255, 255, 0\.34\)[^}]*inset 0 -1px 0 rgba\(2, 5, 11, 0\.58\)[^}]*0 14px 34px rgba\(0, 0, 0, 0\.44\)/s,
  )
  assert.match(css, /\.screen--echo-void \.echo-confirm::before\s*\{[^}]*pointer-events:\s*none;[^}]*box-shadow:/s)
  assert.match(css, /\.screen--echo-void \.echo-confirm::after\s*\{[^}]*pointer-events:\s*none;[^}]*animation:\s*echo-glass-sheen 7\.5s/s)
})

test('the dark-glass control has restrained hover, tactile press, and motion-safe sheen', () => {
  assert.match(css, /\.screen--echo-void \.echo-confirm:hover\s*\{[^}]*border-color:\s*rgba\(235, 240, 250, 0\.5\);/s)
  assert.match(
    css,
    /\.screen--echo-void \.echo-confirm:active\s*\{[^}]*transform:\s*translateY\(1px\) scale\(0\.965\);[^}]*backdrop-filter:\s*blur\(34px\) saturate\(175%\) brightness\(88%\);/s,
  )
  assert.match(css, /@keyframes echo-glass-sheen\s*\{/)
  assert.match(
    css,
    /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.screen--echo-void \.echo-confirm::before,[\s\S]*\.screen--echo-void \.echo-confirm::after\s*\{[^}]*animation:\s*none;[^}]*transition:\s*none;/s,
  )
})

test('the glass filter stays standard-property-only in the component override', () => {
  const restingRule = css.match(/\.screen--echo-void \.echo-confirm\s*\{([^}]*)\}/s)?.[1] ?? ''
  const activeRule = css.match(/\.screen--echo-void \.echo-confirm:active\s*\{([^}]*)\}/s)?.[1] ?? ''

  assert.match(restingRule, /backdrop-filter:\s*blur\(30px\) saturate\(165%\) brightness\(82%\);/)
  assert.match(activeRule, /backdrop-filter:\s*blur\(34px\) saturate\(175%\) brightness\(88%\);/)
  assert.doesNotMatch(restingRule, /-webkit-backdrop-filter\s*:/)
  assert.doesNotMatch(activeRule, /-webkit-backdrop-filter\s*:/)
})

test('the old bottom dot row becomes a close-fitting radial tick ring', () => {
  assert.match(css, /\.mood-orbit-steps\s*\{[^}]*position:\s*absolute;[^}]*inset:\s*0;[^}]*pointer-events:\s*none;/s)
  assert.match(css, /\.mood-orbit-step\s*\{[^}]*left:\s*50%;[^}]*top:\s*50%;[^}]*width:\s*28px;[^}]*height:\s*28px;/s)
  assert.match(css, /\.mood-orbit-step::before\s*\{[^}]*width:\s*1px;[^}]*height:\s*13px;[^}]*border-radius:\s*999px;/s)
  assert.match(css, /\.mood-orbit-step\[data-active\]::before\s*\{[^}]*height:\s*22px;[^}]*background:\s*rgba\(246, 247, 250, 0\.96\);/s)
  assert.doesNotMatch(css, /grid-template-columns:\s*repeat\(15, 1fr\)/)
})

test('the planet hit target and all revealed mood words use restrained clickable styling', () => {
  assert.match(css, /\.mood-orbit-toggle\s*\{[^}]*width:\s*210px;[^}]*height:\s*210px;[^}]*pointer-events:\s*auto;/s)
  assert.match(css, /\.mood-orbit-texts\s*\{[^}]*position:\s*absolute;[^}]*inset:\s*0;[^}]*pointer-events:\s*none;/s)
  assert.match(css, /\.mood-orbit-text\s*\{[^}]*appearance:\s*none;[^}]*padding:\s*8px 10px;[^}]*border:\s*0;[^}]*background:\s*transparent;[^}]*font-family:\s*var\(--serif\);[^}]*pointer-events:\s*none;[^}]*transition:[^}]*opacity 320ms/s)
  assert.match(css, /\.mood-orbit-text\[data-visible\]\s*\{[^}]*pointer-events:\s*auto;/s)
  assert.match(css, /\.mood-orbit-text\[data-active\]\s*\{[^}]*font-size:\s*28px;/s)
  assert.match(css, /\.mood-orbit-text:focus-visible\s*\{[^}]*outline:\s*none;[^}]*text-shadow:/s)
  assert.match(css, /@media \(prefers-reduced-motion: reduce\)[\s\S]*\.mood-orbit-text/s)
})
