# HarmonyOS UI refinement verification — 2026-09-15

## Changes

- Timeline: equal-width, 132 vp tall list cards, 12 vp corners, 10 vp spacing; separate date/type and mood rows; whitespace-normalized two-line previews with ellipsis.
- Account entry renamed 我的. Added account summary, memory count, email/login information, expandable email-verified password change, data storage explanation, sign-out confirmation and existing account deletion confirmation.
- Password management uses the existing AGC provider. Authenticated reset methods retain the local session on errors, validate inputs, and enforce the existing resend cooldown. Local owner accounts have no remote password controls.
- Home word selection resets on returning between mood/word steps and after handing a copied selection to navigation. Focused and manually selected words share white, enlarged, medium-weight text and text glow.
- Starfield ports Web Starfield.tsx's density (one star per 4200 square layout units), size, lavender color, sinusoidal opacity and drift speed. It integrates elapsed time at 30 Hz, wraps edges, pauses when hidden and cleans up on disappearance. Existing tap scatter is preserved. Aurora gradients now fade to transparent to avoid hard pill edges.

## Reproduction and device checks

Device: existing local emulator `127.0.0.1:5555`, API 24 application `com.milo.echoes`.

1. Before replacing the installed app: enter the word ring, select 开朗, return to the mood dial, enter again. The selected summary still contained 开朗. This reproduces the stale selection on the return/reselect path. Existing filtered hilog output did not contain a matching interaction record; no claim of a logged exception.
2. After installing the modified app: choose 还不错, select 舒心, return and re-enter. 舒心 disappears from the selected summary and returns to normal size. The same path was retested after the text-glow refinement.
3. Selected 舒心 and default focused 还不错 use the same enlarged white text glow. Replaced generic shadow with textShadow after screenshot review exposed a rectangular glow.
4. Opened the timeline with four existing entries. Cards share equal bounds; longer contents truncate. No existing entries were removed or edited.
5. Opened 我的 and expanded 修改密码. Verified that the scrollable form exposes code, password, confirmation and save controls. No verification email was sent and no real account password was changed.
6. Compared runtime star layout snapshots: both coordinates and opacity change while idle (for example, one sampled star moved from [649,1273] to [645,1280], opacity 0.443580 to 0.666274). This verifies actual animation rather than relying only on source inspection.

## Automated checks

- `./hvigorw test`: 162 passed, 0 failures, 0 errors. Includes new second-recording label isolation and authenticated password-management tests.
- Bundled Node `--test tests/shell-contract.test.mjs`: 3 passed.
- `./hvigorw assembleHap`: signed debug build successful.
- `git diff --check`: passed.

Real AGC email delivery/password change still requires an owner-driven test. Web and native rasterization are different; this is a native port of Web motion behavior, not a claim of pixel-identical rendering on every device.
