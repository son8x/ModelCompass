// quota-common.js — module dùng chung cho "quota bar" đa provider (Phase 1.4)
//
// Mục tiêu: tách phần CHUNG ra khỏi xkiro-statusline thành 1 module duy nhất:
//   - Đăng ký provider nào được bật (env QUOTA_PROVIDERS, mặc định "xkiro").
//   - Map provider → cache dir (giữ nguyên đường dẫn cũ cho xKiro để tương thích
//     với xkiro-usage.js đang chạy).
//   - Chuẩn hoá dữ liệu quota → { text, tone } dùng cho status bar.
//
// Adapter mới (provider khác xKiro): trả về null/ném lỗi → statusline dùng
// fallback "không có quota API" thay vì vỡ nếu API không tồn tại.

import { createUsageStore } from "./xkiro-store.js"
import { join } from "node:path"

function env(name) {
  try {
    return globalThis.process?.env?.[name]
  } catch {
    return undefined
  }
}

function cacheBase() {
  const home = env("USERPROFILE") || env("HOME") || env("LOCALAPPDATA") || "."
  const base = env("XDG_CACHE_HOME") || join(home, ".cache")
  return base
}

// Danh sách provider được bật. Mặc định "xkiro" (giữ nguyên hành vi cũ);
// bật thêm bằng: QUOTA_PROVIDERS=xkiro,teamo
export function activeProviders() {
  const raw = env("QUOTA_PROVIDERS")
  if (!raw) return ["xkiro"]
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
}

// Cache dir của từng provider.
// - xKiro: GIỮ NGUYÊN đường đi cũ (mặc định ~/.cache/xkiro) để không làm lệch
//   với xkiro-usage.js (server plugin) — nó vẫn ghi cache mà statusline đọc.
// - provider khác: <QUOTA_CACHE_DIR || ~/.cache>/quota/<provider>/
export function providerDir(name) {
  if (name === "xkiro") {
    return env("XKIRO_USAGE_CACHE_DIR") || join(cacheBase(), "xkiro")
  }
  const base = env("QUOTA_CACHE_DIR") || join(cacheBase(), "quota")
  return join(base, name)
}

// Store dùng chung (xkiro-store.js đã generic, chỉ cần chỉ dir).
export function createQuotaStore(name, options = {}) {
  return createUsageStore({ ...options, dir: options.dir || providerDir(name) })
}

// Key cho adapter xKiro — không bao giờ in/lưu key.
export function xkiroKey() {
  return env("XTROUTER_API_KEY") || env("XKIRO_API_KEY")
}

export const QUOTA_URLS = Object.freeze({
  xkiro: "https://api.xkiro.com/v1/usage",
})

// Chuẩn hoá dữ liệu /v1/usage của xKiro → chuỗi hiển thị + tone.
// Ctrl: OK khi mọi hạn mức < WARN_PCT; WARN >= WARN_PCT; ERR khi >= 100%.
export function summarizeXKiro(data, warnPct = 90) {
  const ft = data.free_tokens || {}
  const limits = {
    free: { cap: Number(ft.limit_per_day) || 0, rem: Number(ft.remaining) || 0, reset: 0 },
    burst: { cap: 0, rem: 0, reset: 0 },
    budget: { cap: 0, rem: 0, reset: 0 },
  }
  for (const w of data.windows || []) {
    const key = w.kind === "short" ? "burst" : "budget"
    limits[key] = {
      cap: Number(w.cap_usd) || 0,
      rem: Number(w.remaining_usd) || 0,
      reset: Number(w.resets_in_sec) || 0,
    }
  }
  const wallet = Number(data.wallet?.balance_usd) || 0

  const pct = (l) => (l.cap > 0 ? (1 - l.rem / l.cap) * 100 : 0)
  const fmtCount = (v) => {
    const n = Number(v ?? 0)
    if (n >= 1e9) return `${(n / 1e9).toFixed(1)}B`
    if (n >= 1e6) return `${(n / 1e6).toFixed(2)}M`
    if (n >= 1e3) return `${(n / 1e3).toFixed(1)}K`
    return String(Math.round(n))
  }
  const fmtUntil = (sec) => {
    const s = Number(sec ?? 0)
    if (s <= 0) return ""
    if (s < 60) return `${Math.max(1, Math.round(s))}s`
    if (s < 3600) return `${Math.floor(s / 60)}m`
    if (s < 86400) {
      const h = Math.floor(s / 3600)
      const m = Math.floor((s % 3600) / 60)
      return m ? `${h}h${m}m` : `${h}h`
    }
    const d = Math.floor(s / 86400)
    const h = Math.floor((s % 86400) / 3600)
    return h ? `${d}d${h}h` : `${d}d`
  }

  const parts = []
  if (limits.free.cap) {
    parts.push(`free ${fmtCount(limits.free.rem)} (${pct(limits.free).toFixed(0)}%)`)
  }
  if (limits.burst.cap) {
    parts.push(`burst $${limits.burst.rem.toFixed(2)} (${pct(limits.burst).toFixed(0)}%, ~${fmtUntil(limits.burst.reset)})`)
  }
  if (limits.budget.cap) {
    parts.push(`budget $${limits.budget.rem.toFixed(2)} (${pct(limits.budget).toFixed(0)}%, ~${fmtUntil(limits.budget.reset)})`)
  }
  parts.push(`wallet $${wallet.toFixed(2)}`)

  const maxPct = Math.max(...Object.values(limits).filter((l) => l.cap > 0).map(pct), 0)
  const tone = maxPct >= 100 ? "err" : maxPct >= warnPct ? "warn" : "ok"
  return { text: `xKiro ${parts.join(" · ")}`, tone }
}