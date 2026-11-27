// チャンネルの投稿に添付されたファイル（画像など）を、Open WebUI からダウンロードしてローカルに保存する。
// 一覧 API では data が true/false に省略されるため、data がある投稿は単体取得して data.files を読む。
// 保存先のパスを本文に付けて Claude Code に渡す（画像は Read ツールで開ける）。

import fs from 'node:fs'
import path from 'node:path'

const safeName = s => String(s || 'file').replace(/[^A-Za-z0-9_.-]/g, '_').slice(-80) || 'file'

export function createAttachmentFetcher({ base, headers, api, log, rootDir, channelName, getChannelId, maxFiles = 10, maxBytes = 20 * 1024 * 1024, keepMs = 7 * 24 * 3600 * 1000 }) {
  const dir = path.join(rootDir, safeName(channelName))

  function purgeOld() {
    try {
      const now = Date.now()
      for (const f of fs.readdirSync(dir)) {
        const p = path.join(dir, f)
        try { if (now - fs.statSync(p).mtimeMs > keepMs) fs.unlinkSync(p) } catch {}
      }
    } catch {}
  }

  return async function fetchAttachments(m) {
    if (!m.data) return []
    let files = m.data?.files
    if (!Array.isArray(files)) {
      const full = await api('GET', `/api/v1/channels/${getChannelId()}/messages/${m.id}`)
      files = full?.data?.files
    }
    if (!Array.isArray(files) || files.length === 0) return []

    fs.mkdirSync(dir, { recursive: true })
    purgeOld()

    const out = []
    for (const [i, f] of files.slice(0, maxFiles).entries()) {
      const id = f.id || f.file?.id
      const name = safeName(f.name || f.file?.filename)
      const type = f.content_type || f.file?.meta?.content_type || ''
      const declared = Number(f.size || f.file?.meta?.size || 0)
      if (!id) continue
      if (declared > maxBytes) { out.push({ name, type, size: declared, error: `大きすぎます（上限 ${maxBytes} bytes）` }); continue }
      try {
        const r = await fetch(`${base}/api/v1/files/${id}/content`, { headers })
        if (!r.ok) throw new Error(`HTTP ${r.status}`)
        const buf = Buffer.from(await r.arrayBuffer())
        if (buf.length > maxBytes) { out.push({ name, type, size: buf.length, error: `大きすぎます（上限 ${maxBytes} bytes）` }); continue }
        const p = path.join(dir, `${String(m.id).slice(0, 8)}-${i}-${name}`)
        fs.writeFileSync(p, buf)
        out.push({ name, type, size: buf.length, path: p })
      } catch (e) {
        log('添付の取得に失敗:', e.message)
        out.push({ name, type, size: declared, error: e.message })
      }
    }
    if (files.length > maxFiles) out.push({ name: `(ほか ${files.length - maxFiles} 件)`, error: `1 投稿あたり ${maxFiles} 件までしか取り込みません` })
    return out
  }
}

export function formatAttachments(atts) {
  if (!atts.length) return ''
  return '\n\n[添付ファイル]\n' + atts.map(a =>
    a.path ? `- ${a.path} (${a.type || '種類不明'}, ${a.size} bytes)` : `- ${a.name}: 取り込めませんでした（${a.error}）`
  ).join('\n')
}
