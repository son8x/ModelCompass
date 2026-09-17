// xkiro-statusline — status bar (slot app_bottom) hiển thị hạn mức xKiro ngay dưới khung chat
//
// - Đăng ký slot `app_bottom` (render dưới active route = dưới khung chat) + toast canary.
// - Đọc GET /v1/usage (miễn phí) định kỳ + refresh khi session.created/idle.
// - Không đọc theme trực tiếp nếu undefined; ép re-render định kỳ.
/** @jsxImportSource @opentui/solid */
import { createRoot, createSignal } from "solid-js"
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"

const USAGE_URL = "https://api.xkiro.com/v1/usage"

function env(name: string): string | undefined {
  try {
    return (globalThis as any).process?.env?.[name] as string | undefined
  } catch {
    return undefined
  }
}

const DISABLED = env("XKIRO_STATUSBAR_DISABLE") === "1" || env("XKIRO_STATUSBAR_DISABLE") === "true"
const REFRESH_MS = (Number(env("XKIRO_STATUSBAR_REFRESH")) || 60) * 1000
const WARN_PCT =
  Number(env("XKIRO_STATUSBAR_WARN_PCT")) ||
  (env("XKIRO_USAGE_WARN_PCT") ? Number(env("XKIRO_USAGE_WARN_PCT")) : 90)

function fmtCount(n: number) {
  const v = Number(n ?? 0)
  if (v >= 1e9) return `${(v / 1e9).toFixed(1)}B`
  if (v >= 1e6) return `${(v / 1e6).toFixed(2)}M`
  if (v >= 1e3) return `${(v / 1e3).toFixed(1)}K`
  return String(Math.round(v))
}

function compact(data: any) {
  const ft = data.free_tokens || {}
  const limits: Record<string, { cap: number; rem: number }> = {
    free: {
      cap: Number(ft.limit_per_day) || 0,
      rem: Number(ft.remaining) || 0,
    },
  }
  for (const w of data.windows || []) {
    const key = w.kind === "short" ? "burst" : "budget"
    limits[key] = {
      cap: Number(w.cap_usd) || 0,
      rem: Number(w.remaining_usd) || 0,
    }
  }
  const wallet = Number(data.wallet?.balance_usd) || 0
  const pct = (l: { cap: number; rem: number }) =>
    l.cap > 0 ? (1 - l.rem / l.cap) * 100 : 0

  const parts: string[] = []
  if (limits.free.cap) {
    parts.push(`free ${fmtCount(limits.free.rem)} (${pct(limits.free).toFixed(0)}%)`)
  }
  if (limits.burst.cap) {
    parts.push(`burst $${limits.burst.rem.toFixed(2)} (${pct(limits.burst).toFixed(0)}%)`)
  }
  if (limits.budget.cap) {
    parts.push(`budget $${limits.budget.rem.toFixed(2)} (${pct(limits.budget).toFixed(0)}%)`)
  }
  parts.push(`wallet $${wallet.toFixed(2)}`)

  const maxPct = Math.max(
    ...[limits.free, limits.burst, limits.budget].filter(
      (l) => l.cap > 0,
    ).map(pct),
    0,
  )
  const tone: "ok" | "warn" | "err" =
    maxPct >= 100 ? "err" : maxPct >= WARN_PCT ? "warn" : "ok"
  return { text: `xKiro ${parts.join(" · ")}`, tone }
}

const FALLBACK: Record<"ok" | "warn" | "err", string> = {
  ok: "white",
  warn: "yellow",
  err: "red",
}

const tui: TuiPlugin = async (api, _options, _meta) => {
  if (DISABLED) return

  try {
    if (typeof api.ui?.toast === "function") {
      api.ui.toast({ variant: "info", title: "xKiro statusline", message: "plugin chạy", duration: 3000 })
    }

    createRoot((dispose) => {
      const [stat, setStat] = createSignal<{ text: string; tone: "ok" | "warn" | "err" }>({
        text: "xKiro · đang đọc...",
        tone: "ok",
      })

      async function refresh() {
        const key = env("XTROUTER_API_KEY") || env("XKIRO_API_KEY")
        if (!key) {
          setStat({ text: "xKiro · thiếu XTROUTER_API_KEY", tone: "warn" })
          return
        }
        try {
          const res = await fetch(USAGE_URL, {
            headers: { Authorization: `Bearer ${key}`, "x-api-key": key },
          })
          if (!res.ok) {
            setStat({ text: `xKiro · API lỗi ${res.status}`, tone: "warn" })
            return
          }
          setStat(compact(await res.json()))
        } catch {
          setStat({ text: "xKiro · không đọc được", tone: "warn" })
        }
      }

      const timer = setInterval(() => void refresh(), REFRESH_MS)
      try { timer.unref?.() } catch { /* noop */ }
      void refresh()

      api.slots.register({
        slots: {
          app_bottom: (ctx) => {
            const s = stat()
            const theme = (ctx.theme as any)?.current
            const fg = theme ? (s.tone === "err" ? theme.error : s.tone === "warn" ? theme.warning : theme.textMuted) : FALLBACK[s.tone]
            return (
              <box paddingLeft={1} paddingRight={1} height={1}>
                <text style={{ fg } as never}>{s.text}</text>
              </box>
            )
          },
        },
      })

      for (const evt of ["session.created", "session.idle"] as const) {
        try {
          api.event.on(evt, () => void refresh())
        } catch { /* bỏ qua */ }
      }

      api.lifecycle.onDispose(() => {
        clearInterval(timer)
        dispose()
      })
    })
  } catch { /* im lặng */ }
}

export default { id: "xkiro-statusline", tui } as TuiPluginModule