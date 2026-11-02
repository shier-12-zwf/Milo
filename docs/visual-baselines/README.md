# Visual Baselines

Pixel-faithful parity ledger for the HarmonyOS native replica. Each entry
pairs a Web source asset with its native copy and records a SHA-256 hash.
Both sides must match byte-for-byte — we never re-encode the source PNGs.

## Mood Sheets

Source: `docs/superpowers/concepts/mood-orbs/*-transparent.png`
Target: `apps/harmony/entry/src/main/resources/base/media/mood_sheet_0[1-5].png`

| Source sheet | Native asset | SHA-256 |
| --- | --- | --- |
| `01-very-low-low-heavy-transparent.png` | `mood_sheet_01.png` | `deeb59d988008fc3a0c3cacac1f9ce1d6514c3f1d8e1be5b13c8fceb70ff336f` |
| `02-calm-okay-bright-transparent.png` | `mood_sheet_02.png` | `d1368d267bf3a6904a4405d5b1dc859067afcfddcefcfcbcdf37eb3598024184` |
| `03-joyful-lonely-sad-transparent.png` | `mood_sheet_03.png` | `f9a055a5c71a4b89b6be099a15b4131fee83b33f973eb19ece1c47814b50b81c` |
| `04-angry-afraid-disappointed-transparent.png` | `mood_sheet_04.png` | `9e7bcba4c31431f31b7fa2ba26b926b207508f8f4f2f1b19b6937f588d87c599` |
| `05-anxious-aggrieved-embarrassed-transparent.png` | `mood_sheet_05.png` | `347cf216c76a1d17d4fbbf36fbe43f8eca4bb223da60112277188804664b8b2d` |

Sheet geometry mirrors `apps/web/src/components/moodOrbAssets.ts`:
- Width `1748`, height `2700` source pixels
- `3` panels per sheet, default focus offsets `[-11, 0, +11]` percent
- `anxious` (sheet 05, panel 0) uses focus offset `-9` to keep its planet centred

The mapping of `MoodId → { sheet, panel, focusOffsetPercent }` is defined in
`apps/harmony/entry/src/main/ets/core/model/MoodAssets.ets` and exercised by
`apps/harmony/entry/src/ohosTest/ets/test/MoodAssets.test.ets`.

## Refresh

To regenerate after any source PNG update:

```bash
cp docs/superpowers/concepts/mood-orbs/01-very-low-low-heavy-transparent.png \
   apps/harmony/entry/src/main/resources/base/media/mood_sheet_01.png
# ...repeat for sheets 02-05
shasum -a 256 docs/superpowers/concepts/mood-orbs/*-transparent.png \
          apps/harmony/entry/src/main/resources/base/media/mood_sheet_*.png
```

Replace the SHA-256 table above if any hash drifts.

## Native Screen Parity (Web → HarmonyOS)

| Web screen | Native component | Viewport | Notes |
| --- | --- | --- | --- |
| `Home` (echo) | `features/home/HomeScreen.ets` | 360 × 720 | Echo orbit + starfield; theme tokens in `core/theme/MiloTheme.ets` |
| `Classify` | `features/recall/ClassifyScreen.ets` | 360 × 720 | Two fork cards, glass background |
| `NowNote` | `features/recall/NowNoteScreen.ets` | 360 × 720 | Mood planet + textarea |
| `PastTime` | `features/recall/PastTimeScreen.ets` | 360 × 720 | 10 preset chips + custom input |
| `Chat` | `features/conversation/ChatScreen.ets` | 360 × 720 | Fallback guide only (offline-first) |
| `Diary` | `features/diary/DiaryScreen.ets` | 360 × 720 | Toggle + first-person draft |
| `Timeline` | `features/timeline/TimelineScreen.ets` | 360 × 720 | Newest-first list of entries |
| `Detail` | `features/timeline/DetailScreen.ets` | 360 × 720 | Diary, optional transcript, share-link entry |
| `Card` | `features/timeline/CardScreen.ets` | 360 × 720 | Sticker template picker; full render in Task 9 |

Screenshots are not committed; capture them on the emulator and attach to
release notes when a visual diff is suspected.