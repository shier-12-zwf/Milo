import { useEffect, useRef, useState } from 'react'
import {
  normalizeStickerTemplate,
  renderCard,
  stickerRenderKey,
  STICKER_TEMPLATES,
} from '../lib/card'
import { updateEntry } from '../store'
import type { Entry, StickerTemplateId } from '../types'

interface Props {
  entry: Entry
  onDone: () => void
  onHome: () => void
}

export function Card({ entry, onDone, onHome }: Props) {
  const [selected, setSelected] = useState<StickerTemplateId>(() =>
    normalizeStickerTemplate(entry.stickerTemplate),
  )
  const [urls, setUrls] = useState<Partial<Record<StickerTemplateId, string>>>({})
  const [renderError, setRenderError] = useState<string | null>(null)
  const [renderRevision, setRenderRevision] = useState(0)
  const renderKey = stickerRenderKey(entry)
  const entryRef = useRef(entry)
  entryRef.current = entry

  useEffect(() => {
    setSelected(normalizeStickerTemplate(entry.stickerTemplate))
  }, [entry.id, entry.stickerTemplate])

  useEffect(() => {
    let active = true
    const controller = new AbortController()
    const entryToRender = entryRef.current
    setUrls({})
    setRenderError(null)

    const run = async () => {
      try {
        if (document.fonts?.ready) {
          await document.fonts.ready.catch(() => undefined)
        }
        const pairs = await Promise.all(
          STICKER_TEMPLATES.map(async (template) => [
            template.id,
            await renderCard(entryToRender, template.id, { signal: controller.signal }),
          ] as const),
        )
        if (active) {
          setUrls(Object.fromEntries(pairs) as Record<StickerTemplateId, string>)
        }
      } catch (error) {
        if (active && !(error instanceof DOMException && error.name === 'AbortError')) {
          setUrls({})
          setRenderError(error instanceof Error ? error.message : '卡片显影失败，请稍后再试。')
          console.error('[Card] 卡片渲染失败', error)
        }
      }
    }
    void run()

    return () => {
      active = false
      controller.abort()
    }
  }, [renderKey, renderRevision])

  const url = urls[selected] ?? null
  const isLoading = !url && !renderError

  const selectTemplate = (next: StickerTemplateId) => {
    setSelected(next)
    updateEntry(entry.id, { stickerTemplate: next })
  }

  const download = () => {
    if (!url) return
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `milo-${entry.timeMark ?? '此刻'}-${selected}.png`
    anchor.click()
  }

  return (
    <main className="screen screen-scroll memory-sticker-screen">
      <header className="topbar">
        <button className="back-link" onClick={onDone}>
          ← 完成
        </button>
      </header>

      <section className="sticker-intro">
        <p className="eyebrow">MILO MEMORY</p>
        <h1 className="title">你的情绪卡片</h1>
        <p className="subtitle">把这颗星球，分享给今天的世界。</p>
      </section>

      <section className="sticker-preview-shell" aria-live="polite" aria-busy={isLoading}>
        {url ? (
          <img
            key={selected}
            className="sticker-preview-image"
            src={url}
            alt={`${STICKER_TEMPLATES.find((item) => item.id === selected)?.name ?? '回忆卡片'}预览`}
          />
        ) : renderError ? (
          <div className="sticker-preview-skeleton sticker-preview-error">
            <span>这次没有显影完成</span>
            <button type="button" onClick={() => setRenderRevision((value) => value + 1)}>
              重新显影
            </button>
          </div>
        ) : (
          <div className="sticker-preview-skeleton">
            <span>卡片显影中…</span>
          </div>
        )}
      </section>

      <section className="template-picker" aria-labelledby="template-title">
        <div className="template-picker-heading">
          <div>
            <p className="template-kicker">LAYOUTS</p>
            <h2 id="template-title">选择卡片模板</h2>
          </div>
          <span>{STICKER_TEMPLATES.findIndex((item) => item.id === selected) + 1} / {STICKER_TEMPLATES.length}</span>
        </div>

        <div className="template-strip">
          {STICKER_TEMPLATES.map((template, index) => {
            const isSelected = template.id === selected
            return (
              <button
                key={template.id}
                className={`template-card${isSelected ? ' is-selected' : ''}`}
                type="button"
                aria-pressed={isSelected}
                onClick={() => selectTemplate(template.id)}
              >
                <span className="template-number">0{index + 1}</span>
                <span className="template-artwork">
                  {urls[template.id] ? (
                    <img src={urls[template.id]} alt="" />
                  ) : (
                    <span className="template-artwork-loading" />
                  )}
                </span>
                <span className="template-name">{template.name}</span>
                <span className="template-tone">{template.tone}</span>
              </button>
            )
          })}
        </div>
      </section>

      {renderError && <p className="sticker-error" role="alert">{renderError}</p>}

      <footer className="sticker-actions">
        <button className="btn" onClick={download} disabled={!url}>
          保存图片
        </button>
        <button className="btn btn-primary" onClick={onHome}>
          回到首页
        </button>
      </footer>
    </main>
  )
}
