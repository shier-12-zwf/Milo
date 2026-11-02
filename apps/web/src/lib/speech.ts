import { useEffect, useRef, useState } from 'react'

/* eslint-disable @typescript-eslint/no-explicit-any */

interface SpeechAPI {
  supported: boolean
  listening: boolean
  /** 实时中间结果 */
  interim: string
  start: () => void
  stop: () => void
}

/**
 * 浏览器语音识别（Web Speech API），最终结果通过 onResult 回调。
 * Chrome / Safari 支持；不支持时 supported = false。
 */
export function useSpeech(onResult: (text: string) => void): SpeechAPI {
  const Ctor =
    typeof window !== 'undefined'
      ? (window as any).SpeechRecognition || (window as any).webkitSpeechRecognition
      : undefined
  const supported = Boolean(Ctor)
  const [listening, setListening] = useState(false)
  const [interim, setInterim] = useState('')
  const recRef = useRef<any>(null)
  const onResultRef = useRef(onResult)
  onResultRef.current = onResult

  useEffect(() => {
    if (!Ctor) return
    const rec = new Ctor()
    rec.lang = 'zh-CN'
    rec.continuous = false
    rec.interimResults = true
    rec.onresult = (ev: any) => {
      let finalText = ''
      let interimText = ''
      for (let i = ev.resultIndex; i < ev.results.length; i++) {
        const r = ev.results[i]
        if (r.isFinal) finalText += r[0].transcript
        else interimText += r[0].transcript
      }
      setInterim(interimText)
      if (finalText) onResultRef.current(finalText)
    }
    rec.onend = () => {
      setListening(false)
      setInterim('')
    }
    rec.onerror = () => {
      setListening(false)
      setInterim('')
    }
    recRef.current = rec
    return () => {
      rec.onresult = null
      rec.onend = null
      rec.onerror = null
      try {
        rec.abort()
      } catch {
        /* noop */
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  return {
    supported,
    listening,
    interim,
    start: () => {
      if (!recRef.current || listening) return
      try {
        recRef.current.start()
        setListening(true)
      } catch {
        /* noop */
      }
    },
    stop: () => {
      recRef.current?.stop()
    },
  }
}
