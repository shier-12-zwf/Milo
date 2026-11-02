import type { MoodId } from '../types'
import { moodColors } from './moodOrbModel.ts'

export type MoodMotion =
  | 'sink'
  | 'settle'
  | 'breathe'
  | 'lift'
  | 'glow'
  | 'spark'
  | 'withdraw'
  | 'rain'
  | 'bristle'
  | 'shiver'
  | 'fade'
  | 'orbit'
  | 'hold'
  | 'wobble'

export interface MoodStroke {
  d: string
  layer: 'face' | 'hand' | 'accent' | 'tear' | 'blush'
  fill?: boolean
}

export interface MoodDynamics {
  flow: [number, number]
  starDensity: number
  lightY: number
  turbulence: number
  pulse: number
}

export interface MoodVisual {
  id: MoodId
  label: string
  valence: number
  palette: [string, string, string]
  ink: string
  blush: string
  accent: string
  motion: MoodMotion
  spinOffset: number
  dynamics: MoodDynamics
  eyes: MoodStroke[]
  brows: MoodStroke[]
  mouth: MoodStroke[]
  hands: MoodStroke[]
  accents: MoodStroke[]
}

export const ECHO_MOODS: readonly MoodVisual[] = [
  {
    id: 'very-low',
    label: '非常低落',
    valence: -3,
    palette: ['#343b5d', '#202530', '#62749a'],
    ink: '#071a4a',
    blush: '#776f8a',
    accent: '#66799f',
    motion: 'sink',
    spinOffset: -4,
    dynamics: { flow: [0, -0.65], starDensity: 0.6, lightY: -0.28, turbulence: 0.2, pulse: 0.05 },
    eyes: [
      { d: 'M76 98 C81 101 87 100 91 96', layer: 'face' },
      { d: 'M109 97 C114 100 121 101 125 96', layer: 'face' },
    ],
    brows: [
      { d: 'M76 88 C82 86 87 87 91 90', layer: 'face' },
      { d: 'M109 90 C114 87 120 87 125 89', layer: 'face' },
    ],
    mouth: [
      { d: 'M91 121 C95 116 98 126 102 120 C106 115 109 124 112 120', layer: 'face' },
    ],
    hands: [
      { d: 'M54 132 C62 148 75 155 94 151 C99 150 101 146 98 143', layer: 'hand' },
      { d: 'M146 131 C137 148 124 154 106 151 C101 150 99 146 102 143', layer: 'hand' },
    ],
    accents: [
      { d: 'M46 78 C41 86 42 93 47 95 C52 92 52 85 46 78', layer: 'tear' },
      { d: 'M157 88 C153 95 154 101 158 103 C162 100 162 94 157 88', layer: 'tear' },
      { d: 'M31 156 C45 176 65 188 91 192', layer: 'accent' },
      { d: 'M109 192 C135 188 155 176 169 156', layer: 'accent' },
    ],
  },
  {
    id: 'low',
    label: '低落',
    valence: -2,
    palette: ['#66738f', '#464b62', '#aaa1c2'],
    ink: '#071a4a',
    blush: '#9a879d',
    accent: '#8790af',
    motion: 'settle',
    spinOffset: -3,
    dynamics: { flow: [0, -0.4], starDensity: 0.75, lightY: -0.18, turbulence: 0.25, pulse: 0.08 },
    eyes: [
      { d: 'M76 94 Q83 101 91 99', layer: 'face' },
      { d: 'M109 99 Q117 101 125 94', layer: 'face' },
    ],
    brows: [
      { d: 'M76 87 Q84 85 91 89', layer: 'face' },
      { d: 'M109 89 Q117 85 125 87', layer: 'face' },
    ],
    mouth: [{ d: 'M91 123 Q101 112 111 121', layer: 'face' }],
    hands: [
      { d: 'M59 139 Q70 149 84 147 Q89 146 91 142', layer: 'hand' },
      { d: 'M141 139 Q130 149 116 147 Q111 146 109 142', layer: 'hand' },
    ],
    accents: [
      { d: 'M123 103 C117 111 118 120 124 122 C130 118 129 110 123 103', layer: 'tear' },
      { d: 'M46 126 C46 134 46 139 45 145', layer: 'accent' },
      { d: 'M155 126 C155 134 154 140 153 146', layer: 'accent' },
    ],
  },
  {
    id: 'heavy',
    label: '有些沉',
    valence: -1,
    palette: ['#716d82', '#4a4958', '#b8b9c8'],
    ink: '#071a4a',
    blush: '#9b8e9f',
    accent: '#9395a8',
    motion: 'settle',
    spinOffset: -2,
    dynamics: { flow: [0.05, -0.25], starDensity: 0.85, lightY: -0.12, turbulence: 0.2, pulse: 0.07 },
    eyes: [
      { d: 'M75 91 Q83 87 92 92 M78 96 Q85 99 91 96', layer: 'face' },
      { d: 'M108 92 Q117 87 126 91 M109 96 Q116 99 123 96', layer: 'face' },
    ],
    brows: [
      { d: 'M75 84 Q83 81 91 84', layer: 'face' },
      { d: 'M109 84 Q118 81 126 84', layer: 'face' },
    ],
    mouth: [{ d: 'M93 120 C98 119 104 121 109 120', layer: 'face' }],
    hands: [
      { d: 'M58 139 Q70 148 84 146 Q89 145 91 141', layer: 'hand' },
      { d: 'M137 143 C128 137 125 125 127 113 C128 108 132 106 135 110', layer: 'hand' },
      { d: 'M127 114 C132 116 137 118 141 119', layer: 'hand' },
    ],
    accents: [
      { d: 'M55 57 Q99 37 146 59', layer: 'accent' },
      { d: 'M150 105 C161 108 166 114 168 121', layer: 'accent' },
    ],
  },
  {
    id: 'calm',
    label: '平静',
    valence: 0,
    palette: ['#d9bfd8', '#887393', '#f5ddec'],
    ink: '#071a4a',
    blush: '#d7a9bd',
    accent: '#aeb7d2',
    motion: 'breathe',
    spinOffset: 0,
    dynamics: { flow: [0.1, 0], starDensity: 1, lightY: 0, turbulence: 0.08, pulse: 0.1 },
    eyes: [
      { d: 'M76 94 Q83 100 91 94', layer: 'face' },
      { d: 'M109 95 Q117 101 125 93', layer: 'face' },
    ],
    brows: [],
    mouth: [{ d: 'M92 117 Q100 126 111 116', layer: 'face' }],
    hands: [
      {
        d: 'M61 137 C69 145 79 148 89 144 C94 142 96 138 93 135 C90 133 87 136 84 139 M62 137 L58 132 M68 141 L64 134 M75 143 L72 135',
        layer: 'hand',
      },
      {
        d: 'M139 137 C131 145 121 148 111 144 C106 142 104 138 107 135 C110 133 113 136 116 139 M138 137 L142 132 M132 141 L136 134 M125 143 L128 135',
        layer: 'hand',
      },
    ],
    accents: [
      { d: 'M68 108 L75 106 M69 113 L77 111', layer: 'blush' },
      { d: 'M125 106 L132 108 M123 111 L131 113', layer: 'blush' },
      { d: 'M158 92 C168 97 170 105 163 111', layer: 'accent' },
      { d: 'M164 119 C174 123 176 132 170 138', layer: 'accent' },
      { d: 'M100 20 C146 20 180 54 180 100 C180 146 146 180 100 180 C54 180 20 146 20 100 C20 54 54 20 100 20', layer: 'accent' },
    ],
  },
  {
    id: 'okay',
    label: '还不错',
    valence: 1,
    palette: ['#c5aeb8', '#8f819d', '#d8c8df'],
    ink: '#071a4a',
    blush: '#dda8ba',
    accent: '#c4afcf',
    motion: 'lift',
    spinOffset: 1,
    dynamics: { flow: [0.15, 0.25], starDensity: 1.08, lightY: 0.08, turbulence: 0.12, pulse: 0.18 },
    eyes: [
      { d: 'M76 92 C76 85 81 82 86 83 C91 84 93 90 91 96 C89 101 80 101 77 96 C76 95 76 94 76 92', layer: 'face' },
      { d: 'M109 92 C109 85 114 82 120 83 C126 85 127 91 124 97 C121 101 113 100 110 96 C109 95 109 94 109 92', layer: 'face' },
      { d: 'M82 90 A2 3 0 1 0 86 90 A2 3 0 1 0 82 90', layer: 'face', fill: true },
      { d: 'M115 90 A2 3 0 1 0 119 90 A2 3 0 1 0 115 90', layer: 'face', fill: true },
    ],
    brows: [
      { d: 'M76 78 Q84 75 91 79', layer: 'face' },
      { d: 'M110 79 Q118 75 125 78', layer: 'face' },
    ],
    mouth: [{ d: 'M92 116 Q101 126 112 115', layer: 'face' }],
    hands: [
      { d: 'M61 137 C70 145 80 148 90 143', layer: 'hand' },
      { d: 'M139 132 C145 124 148 115 146 105 M145 114 L151 108 M145 116 L153 116 M143 119 L150 124', layer: 'hand' },
    ],
    accents: [
      { d: 'M157 53 L160 61 L168 64 L160 67 L157 75 L154 67 L146 64 L154 61 Z', layer: 'accent' },
      { d: 'M37 92 A5 5 0 1 0 47 92 A5 5 0 1 0 37 92', layer: 'accent' },
      { d: 'M28 111 C20 80 35 48 63 32', layer: 'accent' },
    ],
  },
  {
    id: 'bright',
    label: '明亮',
    valence: 2,
    palette: ['#eadbc5', '#c6ad78', '#f1edf0'],
    ink: '#071a4a',
    blush: '#e7a9b0',
    accent: '#e7cc8e',
    motion: 'glow',
    spinOffset: 2,
    dynamics: { flow: [0.1, 0.45], starDensity: 1.25, lightY: 0.18, turbulence: 0.15, pulse: 0.3 },
    eyes: [
      { d: 'M75 95 Q83 84 92 95', layer: 'face' },
      { d: 'M108 95 Q117 83 126 94', layer: 'face' },
    ],
    brows: [
      { d: 'M76 80 Q84 75 92 80', layer: 'face' },
      { d: 'M108 80 Q117 75 125 79', layer: 'face' },
    ],
    mouth: [{ d: 'M90 115 Q100 130 113 114', layer: 'face' }],
    hands: [
      { d: 'M58 132 C49 128 45 120 47 112 M53 126 L45 127 M55 123 L49 117 M58 123 L57 114', layer: 'hand' },
      { d: 'M142 132 C151 128 155 120 153 112 M147 126 L155 127 M145 123 L151 117 M142 123 L143 114', layer: 'hand' },
    ],
    accents: [
      { d: 'M71 108 L78 106 M70 113 L78 111', layer: 'blush' },
      { d: 'M123 106 L130 108 M122 111 L130 113', layer: 'blush' },
      { d: 'M43 57 L46 65 L54 68 L46 71 L43 79 L40 71 L32 68 L40 65 Z', layer: 'accent' },
      { d: 'M161 73 L164 80 L171 83 L164 86 L161 93 L158 86 L151 83 L158 80 Z', layer: 'accent' },
      { d: 'M139 31 L141 37 L147 39 L141 41 L139 47 L137 41 L131 39 L137 37 Z', layer: 'accent' },
      { d: 'M100 18 C148 18 182 52 182 100 C182 148 148 182 100 182 C52 182 18 148 18 100 C18 52 52 18 100 18', layer: 'accent' },
    ],
  },
  {
    id: 'joyful',
    label: '雀跃',
    valence: 3,
    palette: ['#d9a99e', '#c77e70', '#f8ddc8'],
    ink: '#071a4a',
    blush: '#eb939f',
    accent: '#f0b48f',
    motion: 'spark',
    spinOffset: 4,
    dynamics: { flow: [0.28, 0.55], starDensity: 1.35, lightY: 0.22, turbulence: 0.3, pulse: 0.45 },
    eyes: [
      { d: 'M73 94 Q83 82 94 94', layer: 'face' },
      { d: 'M106 94 Q117 81 128 93', layer: 'face' },
    ],
    brows: [
      { d: 'M76 78 Q83 74 90 78', layer: 'face' },
      { d: 'M110 78 Q117 73 124 77', layer: 'face' },
    ],
    mouth: [{ d: 'M89 113 C94 108 108 108 114 113 C113 126 106 132 101 132 C95 131 90 125 89 113 Z', layer: 'face' }],
    hands: [
      { d: 'M61 126 C52 117 49 105 54 95 M53 105 L45 100 M54 102 L51 92 M57 104 L62 95', layer: 'hand' },
      { d: 'M139 126 C148 116 151 104 146 94 M147 104 L155 99 M146 101 L149 91 M143 103 L138 94', layer: 'hand' },
    ],
    accents: [
      { d: 'M33 103 A4 4 0 1 0 41 103 A4 4 0 1 0 33 103', layer: 'accent' },
      { d: 'M160 109 A5 5 0 1 0 170 109 A5 5 0 1 0 160 109', layer: 'accent' },
      { d: 'M100 24 A3 3 0 1 0 106 24 A3 3 0 1 0 100 24', layer: 'accent' },
      { d: 'M47 57 L53 63 M54 52 L58 58 M148 50 L144 58 M156 57 L150 62', layer: 'accent' },
      { d: 'M31 139 C22 130 21 119 26 111', layer: 'accent' },
      { d: 'M169 140 C179 130 179 118 174 109', layer: 'accent' },
    ],
  },
  {
    id: 'lonely',
    label: '孤独',
    valence: -2,
    palette: ['#aa8796', '#81738d', '#a7a6b2'],
    ink: '#071a4a',
    blush: '#bd8e9e',
    accent: '#928da3',
    motion: 'withdraw',
    spinOffset: -1,
    dynamics: { flow: [-0.15, -0.05], starDensity: 0.55, lightY: -0.08, turbulence: 0.08, pulse: 0.05 },
    eyes: [
      { d: 'M79 103 C80 96 85 94 90 97 C94 100 93 108 89 111 C84 113 79 109 79 103', layer: 'face' },
      { d: 'M108 103 C109 96 114 94 119 97 C123 101 122 108 118 111 C113 113 108 109 108 103', layer: 'face' },
      { d: 'M85 103 A2 3 0 1 0 89 103 A2 3 0 1 0 85 103', layer: 'face', fill: true },
      { d: 'M114 103 A2 3 0 1 0 118 103 A2 3 0 1 0 114 103', layer: 'face', fill: true },
    ],
    brows: [
      { d: 'M79 91 Q85 88 92 92', layer: 'face' },
      { d: 'M108 92 Q115 88 121 91', layer: 'face' },
    ],
    mouth: [{ d: 'M94 122 Q101 117 108 122', layer: 'face' }],
    hands: [
      { d: 'M55 131 C68 141 79 148 100 151 C110 152 116 148 113 143', layer: 'hand' },
      { d: 'M145 132 C132 142 121 148 100 151 C90 152 84 148 87 143', layer: 'hand' },
    ],
    accents: [
      { d: 'M53 37 C28 57 18 88 24 117 C27 132 34 144 44 154', layer: 'accent' },
      { d: 'M155 37 C170 49 179 64 182 80', layer: 'accent' },
      { d: 'M163 55 A4 4 0 1 0 171 55 A4 4 0 1 0 163 55', layer: 'accent' },
      { d: 'M180 44 A3 3 0 1 0 186 44 A3 3 0 1 0 180 44', layer: 'accent' },
      { d: 'M193 36 A2 2 0 1 0 197 36 A2 2 0 1 0 193 36', layer: 'accent' },
    ],
  },
  {
    id: 'sad',
    label: '悲伤',
    valence: -3,
    palette: ['#779abd', '#8f86b0', '#c8ced8'],
    ink: '#071a4a',
    blush: '#ab91b0',
    accent: '#91acd0',
    motion: 'rain',
    spinOffset: -2,
    dynamics: { flow: [0, -0.5], starDensity: 0.75, lightY: -0.2, turbulence: 0.35, pulse: 0.12 },
    eyes: [
      { d: 'M75 91 Q83 86 92 93 Q84 101 76 97', layer: 'face' },
      { d: 'M108 93 Q117 86 126 91 Q125 99 116 101', layer: 'face' },
    ],
    brows: [
      { d: 'M75 84 Q84 79 92 85', layer: 'face' },
      { d: 'M108 85 Q117 79 126 84', layer: 'face' },
    ],
    mouth: [{ d: 'M90 123 C94 116 98 127 102 121 C106 116 110 125 114 121', layer: 'face' }],
    hands: [
      { d: 'M59 139 C69 148 81 149 91 143', layer: 'hand' },
      { d: 'M122 137 C128 132 133 131 139 134 C144 137 145 142 142 147 C137 150 130 149 126 145', layer: 'hand' },
      { d: 'M126 128 L139 126 L144 138 L132 142 L122 135 Z', layer: 'hand' },
    ],
    accents: [
      { d: 'M82 101 C76 111 77 121 83 124 C89 120 88 111 82 101', layer: 'tear' },
      { d: 'M119 101 C113 111 114 121 120 124 C126 120 125 111 119 101', layer: 'tear' },
      { d: 'M45 69 C39 78 40 86 46 89 C52 85 51 77 45 69', layer: 'tear' },
      { d: 'M158 82 C153 90 154 98 159 100 C164 96 164 89 158 82', layer: 'tear' },
      { d: 'M35 107 L31 121 M169 109 L165 125', layer: 'accent' },
    ],
  },
  {
    id: 'angry',
    label: '愤怒',
    valence: -2,
    palette: ['#d4716b', '#bd623f', '#4b4850'],
    ink: '#071a4a',
    blush: '#de7673',
    accent: '#e28a5b',
    motion: 'bristle',
    spinOffset: 3,
    dynamics: { flow: [0.55, 0.05], starDensity: 1.15, lightY: 0, turbulence: 1, pulse: 0.5 },
    eyes: [
      { d: 'M75 91 L91 96 Q84 101 76 97', layer: 'face' },
      { d: 'M109 96 L126 91 Q125 98 117 101', layer: 'face' },
    ],
    brows: [
      { d: 'M75 82 L93 89', layer: 'face' },
      { d: 'M107 89 L126 82', layer: 'face' },
    ],
    mouth: [{ d: 'M91 124 C94 116 98 126 102 119 C106 126 110 116 113 124', layer: 'face' }],
    hands: [
      { d: 'M57 135 L63 126 L72 128 L76 137 L69 144 L60 141 Z M62 128 L60 122 M68 128 L68 121 M73 131 L77 125', layer: 'hand' },
      { d: 'M143 135 L137 126 L128 128 L124 137 L131 144 L140 141 Z M138 128 L140 122 M132 128 L132 121 M127 131 L123 125', layer: 'hand' },
    ],
    accents: [
      { d: 'M67 109 Q72 104 78 110 M122 110 Q128 104 133 109', layer: 'blush' },
      { d: 'M150 49 L158 42 L157 52 L168 49 L161 59', layer: 'accent' },
      { d: 'M39 72 L47 76 L42 83 M162 76 L170 72 L166 83', layer: 'accent' },
      { d: 'M28 106 L20 104 M30 116 L21 118 M172 105 L180 102 M170 116 L179 119', layer: 'accent' },
    ],
  },
  {
    id: 'afraid',
    label: '害怕',
    valence: -2,
    palette: ['#d9bb78', '#eee2be', '#595862'],
    ink: '#071a4a',
    blush: '#d5a58e',
    accent: '#d5b66c',
    motion: 'shiver',
    spinOffset: -5,
    dynamics: { flow: [0, 0], starDensity: 0.7, lightY: 0, turbulence: 0.65, pulse: 0.55 },
    eyes: [
      { d: 'M73 91 C73 79 81 75 89 80 C96 86 93 100 84 103 C77 103 73 98 73 91', layer: 'face' },
      { d: 'M108 90 C108 80 115 76 123 80 C130 85 128 99 120 102 C112 102 108 97 108 90', layer: 'face' },
      { d: 'M81 89 A3 4 0 1 0 87 89 A3 4 0 1 0 81 89', layer: 'face', fill: true },
      { d: 'M116 89 A3 4 0 1 0 122 89 A3 4 0 1 0 116 89', layer: 'face', fill: true },
    ],
    brows: [
      { d: 'M73 70 Q83 65 92 72', layer: 'face' },
      { d: 'M108 72 Q118 65 127 70', layer: 'face' },
    ],
    mouth: [{ d: 'M94 117 C94 110 99 107 104 109 C110 111 110 120 105 124 C99 127 94 123 94 117 Z', layer: 'face' }],
    hands: [
      { d: 'M58 130 C65 123 69 114 70 104 M66 116 L60 109 M68 112 L65 103 M70 113 L73 104', layer: 'hand' },
      { d: 'M142 130 C135 123 131 114 130 104 M134 116 L140 109 M132 112 L135 103 M130 113 L127 104', layer: 'hand' },
    ],
    accents: [
      { d: 'M48 55 C42 65 43 74 49 77 C55 73 54 64 48 55', layer: 'tear' },
      { d: 'M159 63 C154 72 155 80 160 83 C166 79 165 71 159 63', layer: 'tear' },
      { d: 'M174 91 C170 98 171 104 175 106 C179 103 179 97 174 91', layer: 'tear' },
      { d: 'M33 90 C30 79 31 70 36 61 M164 125 C170 116 172 107 171 98', layer: 'accent' },
    ],
  },
  {
    id: 'disappointed',
    label: '失望',
    valence: -2,
    palette: ['#77aeb7', '#687a91', '#bcc7d2'],
    ink: '#071a4a',
    blush: '#98a4b2',
    accent: '#83a7b4',
    motion: 'fade',
    spinOffset: -3,
    dynamics: { flow: [0.1, -0.3], starDensity: 0.65, lightY: -0.18, turbulence: 0.3, pulse: 0.06 },
    eyes: [
      { d: 'M75 94 Q83 86 92 95', layer: 'face' },
      { d: 'M108 95 Q117 86 126 94', layer: 'face' },
    ],
    brows: [
      { d: 'M75 82 Q84 78 92 83', layer: 'face' },
      { d: 'M108 83 Q117 78 126 82', layer: 'face' },
    ],
    mouth: [{ d: 'M92 120 C98 116 104 122 110 118 M112 117 C118 117 122 120 124 124', layer: 'face' }],
    hands: [
      { d: 'M59 139 C70 147 81 149 91 143', layer: 'hand' },
      { d: 'M119 143 C127 138 134 138 140 142', layer: 'hand' },
      { d: 'M126 134 L141 132 L145 143 L132 148 L122 141 Z', layer: 'hand' },
    ],
    accents: [
      { d: 'M42 61 L34 75 M64 49 L56 64 M147 46 L139 61 M169 63 L161 77', layer: 'accent' },
      { d: 'M158 102 L160 108 L166 110 L160 112 L158 118 L156 112 L150 110 L156 108 Z', layer: 'accent' },
      { d: 'M154 120 C163 124 167 130 167 137', layer: 'accent' },
    ],
  },
  {
    id: 'anxious',
    label: '焦虑',
    valence: -1,
    palette: ['#a9c8b9', '#7f948b', '#c7cfcd'],
    ink: '#071a4a',
    blush: '#b7a4a3',
    accent: '#91afa4',
    motion: 'orbit',
    spinOffset: 5,
    dynamics: { flow: [0.45, 0.15], starDensity: 0.95, lightY: 0, turbulence: 0.75, pulse: 0.35 },
    eyes: [
      { d: 'M76 94 Q84 86 92 94', layer: 'face' },
      { d: 'M109 92 Q118 84 127 92', layer: 'face' },
      { d: 'M83 91 A2 2.6 0 1 0 87 91 A2 2.6 0 1 0 83 91', layer: 'face', fill: true },
      { d: 'M116 91 A2 2.6 0 1 0 120 91 A2 2.6 0 1 0 116 91', layer: 'face', fill: true },
    ],
    brows: [
      { d: 'M74 78 Q83 72 93 82', layer: 'face' },
      { d: 'M107 82 Q117 72 127 78', layer: 'face' },
    ],
    mouth: [{ d: 'M90 119 L95 115 L100 121 L105 115 L111 121', layer: 'face' }],
    hands: [
      { d: 'M57 133 C65 125 69 115 71 104 M66 117 L60 112 M69 112 L66 105 M70 115 L75 107', layer: 'hand' },
      { d: 'M143 133 C135 125 131 115 129 104 M134 117 L140 112 M131 112 L134 105 M130 115 L125 107', layer: 'hand' },
    ],
    accents: [
      { d: 'M8 54 C-8 43 -13 58 1 64 C15 71 15 84 1 88 C-10 91 -15 82 -9 75 C-3 68 8 75 5 82', layer: 'accent' },
      { d: 'M42 82 C37 90 38 97 43 100 C48 97 48 89 42 82', layer: 'tear' },
      { d: 'M160 116 C155 124 156 131 161 134 C166 130 166 123 160 116', layer: 'tear' },
      { d: 'M28 117 L20 123 M32 128 L25 136 M172 103 L181 99 M170 132 L178 138', layer: 'accent' },
    ],
  },
  {
    id: 'aggrieved',
    label: '委屈',
    valence: -2,
    palette: ['#9dbbd7', '#b0a5ce', '#dda8bd'],
    ink: '#071a4a',
    blush: '#df9fb8',
    accent: '#b3b4d5',
    motion: 'hold',
    spinOffset: -1,
    dynamics: { flow: [0, -0.1], starDensity: 0.9, lightY: 0.02, turbulence: 0.2, pulse: 0.15 },
    eyes: [
      { d: 'M74 84 C79 75 90 75 95 84 C99 94 94 104 85 106 C76 106 70 95 74 84 Z', layer: 'face', fill: true },
      { d: 'M108 84 C113 75 124 75 129 84 C133 94 128 104 119 106 C110 106 104 95 108 84 Z', layer: 'face', fill: true },
    ],
    brows: [
      { d: 'M71 68 Q81 62 93 72', layer: 'face' },
      { d: 'M103 72 Q115 62 126 68', layer: 'face' },
    ],
    mouth: [{ d: 'M92 121 C96 116 99 116 102 121 C105 116 109 117 112 122 Q102 128 92 121', layer: 'face' }],
    hands: [
      { d: 'M66 132 C76 126 85 127 99 139 C102 142 100 147 96 147 C87 142 78 138 68 139', layer: 'hand' },
      { d: 'M134 132 C124 126 115 127 101 139 C98 142 100 147 104 147 C113 142 122 138 132 139', layer: 'hand' },
    ],
    accents: [
      { d: 'M63 102 A6 6 0 1 0 75 102 A6 6 0 1 0 63 102', layer: 'tear', fill: true },
      { d: 'M128 103 A7 7 0 1 0 142 103 A7 7 0 1 0 128 103', layer: 'tear', fill: true },
      { d: 'M79 83 A2.6 2.6 0 1 0 84.2 83 A2.6 2.6 0 1 0 79 83', layer: 'tear', fill: true },
      { d: 'M113 83 A2.6 2.6 0 1 0 118.2 83 A2.6 2.6 0 1 0 113 83', layer: 'tear', fill: true },
      { d: 'M51 43 C77 22 119 18 150 39 C169 52 179 72 177 94', layer: 'accent' },
      { d: 'M176 109 C173 133 160 153 140 165', layer: 'accent' },
      { d: 'M69 111 L76 109 M68 116 L76 114 M123 109 L131 111 M123 114 L131 116', layer: 'blush' },
    ],
  },
  {
    id: 'embarrassed',
    label: '尴尬',
    valence: -1,
    palette: ['#ce8fba', '#a96c9e', '#c8c1cf'],
    ink: '#071a4a',
    blush: '#e780aa',
    accent: '#c690ba',
    motion: 'wobble',
    spinOffset: 4,
    dynamics: { flow: [0.35, 0], starDensity: 1.05, lightY: 0.03, turbulence: 0.35, pulse: 0.22 },
    eyes: [
      { d: 'M73 92 Q82 98 92 90', layer: 'face' },
      { d: 'M108 90 Q117 96 127 88', layer: 'face' },
      { d: 'M85 92 A2 2.8 0 1 0 89 92 A2 2.8 0 1 0 85 92', layer: 'face', fill: true },
      { d: 'M120 90 A2 2.8 0 1 0 124 90 A2 2.8 0 1 0 120 90', layer: 'face', fill: true },
    ],
    brows: [
      { d: 'M73 77 Q81 73 90 78', layer: 'face' },
      { d: 'M109 79 Q118 73 127 75', layer: 'face' },
    ],
    mouth: [{ d: 'M95 116 C95 111 100 109 105 111 C110 114 109 121 104 123 C99 125 95 122 95 116 Z', layer: 'face' }],
    hands: [
      { d: 'M68 137 C77 130 87 131 96 139 C99 142 97 146 93 146 C85 142 78 141 70 143', layer: 'hand' },
      { d: 'M132 137 C123 130 113 131 104 139 C101 142 103 146 107 146 C115 142 122 141 130 143', layer: 'hand' },
    ],
    accents: [
      { d: 'M65 105 L74 102 M64 111 L75 108 M65 117 L76 113', layer: 'blush' },
      { d: 'M124 102 L135 105 M124 108 L136 111 M124 113 L135 117', layer: 'blush' },
      { d: 'M46 55 C41 63 42 70 47 73 C52 69 51 62 46 55', layer: 'tear' },
      { d: 'M158 60 C154 67 155 73 159 75 C163 72 163 66 158 60', layer: 'tear' },
      { d: 'M173 83 C170 89 171 94 175 96 C178 93 178 88 173 83', layer: 'tear' },
      { d: 'M36 69 C53 35 91 20 126 29 C157 37 179 63 179 92 C180 112 168 125 154 128', layer: 'accent' },
      { d: 'M29 118 L20 121 M33 130 L25 137 M164 135 L172 142', layer: 'accent' },
    ],
  },
]

const MOODS_BY_ID = new Map(ECHO_MOODS.map((mood) => [mood.id, mood]))

const LEGACY_LABELS = ['非常低落', '低落', '有些沉', '平静', '还不错', '明亮', '雀跃'] as const

export const DEFAULT_ECHO_MOOD_INDEX = ECHO_MOODS.findIndex(({ id }) => id === 'calm')

export function getMoodVisual(id: MoodId): MoodVisual {
  const mood = MOODS_BY_ID.get(id)
  if (!mood) throw new RangeError(`Unknown mood: ${id}`)
  return mood
}

export function moodLabel(valence: number, id?: MoodId): string {
  if (id !== undefined) return getMoodVisual(id).label
  const level = Math.max(-3, Math.min(3, Math.round(valence)))
  return LEGACY_LABELS[level + 3]
}

export function moodPalette(valence: number, id?: MoodId): [string, string, string] {
  return id === undefined ? moodColors(valence) : getMoodVisual(id).palette
}
