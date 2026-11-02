import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import test from 'node:test'
import { inflateSync } from 'node:zlib'

import { getMoodOrbAsset } from '../src/components/moodOrbAssets.ts'

interface RgbaPng {
  readonly width: number
  readonly height: number
  alphaAt(x: number, y: number): number
}

function paeth(a: number, b: number, c: number): number {
  const estimate = a + b - c
  const distanceA = Math.abs(estimate - a)
  const distanceB = Math.abs(estimate - b)
  const distanceC = Math.abs(estimate - c)
  if (distanceA <= distanceB && distanceA <= distanceC) return a
  return distanceB <= distanceC ? b : c
}

function readRgbaPng(path: string): RgbaPng {
  const png = readFileSync(path)
  assert.deepEqual(png.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))

  let cursor = 8
  let width = 0
  let height = 0
  const compressed: Buffer[] = []

  while (cursor < png.length) {
    const length = png.readUInt32BE(cursor)
    const type = png.toString('ascii', cursor + 4, cursor + 8)
    const data = png.subarray(cursor + 8, cursor + 8 + length)
    cursor += length + 12

    if (type === 'IHDR') {
      width = data.readUInt32BE(0)
      height = data.readUInt32BE(4)
      assert.equal(data[8], 8, 'Alpha regression test expects an 8-bit PNG')
      assert.equal(data[9], 6, 'Alpha regression test expects an RGBA PNG')
      assert.equal(data[12], 0, 'Alpha regression test expects a non-interlaced PNG')
    } else if (type === 'IDAT') {
      compressed.push(data)
    } else if (type === 'IEND') {
      break
    }
  }

  const bytesPerPixel = 4
  const stride = width * bytesPerPixel
  const filtered = inflateSync(Buffer.concat(compressed))
  const pixels = Buffer.alloc(stride * height)
  let sourceOffset = 0

  for (let y = 0; y < height; y += 1) {
    const filter = filtered[sourceOffset]
    sourceOffset += 1
    const rowOffset = y * stride

    for (let x = 0; x < stride; x += 1) {
      const raw = filtered[sourceOffset + x]
      const left = x >= bytesPerPixel ? pixels[rowOffset + x - bytesPerPixel] : 0
      const up = y > 0 ? pixels[rowOffset - stride + x] : 0
      const upperLeft = y > 0 && x >= bytesPerPixel ? pixels[rowOffset - stride + x - bytesPerPixel] : 0
      let value: number

      if (filter === 0) value = raw
      else if (filter === 1) value = raw + left
      else if (filter === 2) value = raw + up
      else if (filter === 3) value = raw + Math.floor((left + up) / 2)
      else if (filter === 4) value = raw + paeth(left, up, upperLeft)
      else throw new Error(`Unsupported PNG filter ${filter}`)

      pixels[rowOffset + x] = value & 0xff
    }

    sourceOffset += stride
  }

  return {
    width,
    height,
    alphaAt(x, y) {
      return pixels[y * stride + x * bytesPerPixel + 3]
    },
  }
}

test('the anxious orb core is opaque instead of a perforated luminance matte', () => {
  const asset = getMoodOrbAsset('anxious')
  const image = readRgbaPng(fileURLToPath(asset.sheet))
  let fullyOpaque = 0
  let sampled = 0

  for (let y = 350; y < 575; y += 1) {
    for (let x = 235; x < 460; x += 1) {
      sampled += 1
      if (image.alphaAt(x, y) === 255) fullyOpaque += 1
    }
  }

  assert.equal(image.alphaAt(346, 456), 255, 'the center of the anxious orb must stay solid')
  assert.ok(fullyOpaque / sampled > 0.98, 'the anxious orb core must not show the page background through speckled alpha')
})
