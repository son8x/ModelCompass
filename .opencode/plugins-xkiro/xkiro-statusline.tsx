// xkiro-statusline — status bar (slot app_bottom) hiển thị hạn mức xKiro
//
// - Đồng bộ giữa MỌI cửa sổ opencode qua shared cache (xkiro-store.js):
//   nhiều nơi hiển thị, nhưng chỉ 1 tiến trình duy nhất gọi GET /v1/usage.
// - Khi cache còn tươi (TTL, mặc định 60s) → chỉ đọc file nội bộ, không gọi mạng.
// - Khi cache cũ → tiến trình giành được lock sẽ fetch + ghi cache; kẻ khác chờ.
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
const RENDER_MS = (Number(env("XKIRO_STATUSBAR_RENDER_MS")) || 5000) as number
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

function fmtUntil(sec: number) {
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

function compact(data: any) {
  const ft = data.free_tokens || {}
  const limits: Record<string, { cap: number; rem: number; reset: number }> = {
    free: {
      cap: Number(ft.limit_per_day) || 0,
      rem: Number(ft.remaining) || 0,
      reset: 0,
    },
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
  const pct = (l: { cap: number; rem: number }) => (l.cap > 0 ? (1 - l.rem / l.cap) * 100 : 0)

  const parts: string[] = []
  if (limits.free.cap) {
    parts.push(`free ${fmtCount(limits.free.rem)} (${pct(limits.free).toFixed(0)}%)`)
  }
  if (limits.burst.cap) {
    parts.push(
      `burst $${limits.burst.rem.toFixed(2)} (${pct(limits.burst).toFixed(0)}%, ~${fmtUntil(limits.burst.reset)})`,
    )
  }
  if (limits.budget.cap) {
    parts.push(
      `budget $${limits.budget.rem.toFixed(2)} (${pct(limits.budget).toFixed(0)}%, ~${fmtUntil(limits.budget.reset)})`,
    )
  }
  parts.push(`wallet $${wallet.toFixed(2)}`)

  const maxPct = Math.max(
    ...[limits.free, limits.burst, limits.budget].filter((l) => l.cap > 0).map(pct),
    0,
  )
  const tone: "ok" | "warn" | "err" = maxPct >= 100 ? "err" : maxPct >= WARN_PCT ? "warn" : "ok"
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
        text: "xKiro · đang đồng bộ...",
        tone: "ok",
      })

      let store: any = null
      void (async () => {
        try {
          const mod = await import("./xkiro-store.js")
          store = mod.createUsageStore()
          const cached = store?.get?.()
          if (cached?.data) setStat(compact(cached.data))
        } catch {
          store = null
          void refresh()
        }
      })()

      async function fetchApi() {
        const key = env("XTROUTER_API_KEY") || env("XKIRO_API_KEY")
        if (!key) {
          setStat({ text: "xKiro · thiếu XTROUTER_API_KEY", tone: "warn" })
          return null
        }
        try {
          const res = await fetch(USAGE_URL, {
            headers: { Authorization: `Bearer ${key}`, "x-api-key": key },
          })
          if (!res.ok) {
            setStat({ text: `xKiro · API lỗi ${res.status}`, tone: "warn" })
            return null
          }
          return await res.json()
        } catch {
          setStat({ text: "xKiro · không đọc được", tone: "warn" })
          return null
        }
      }

      async function refresh() {
        if (store) {
          const res = await store.resolve(fetchApi)
          if (res.data) setStat(compact(res.data))
        } else {
          const data = await fetchApi()
          if (data) setStat(compact(data))
        }
      }

      const timer = setInterval(() => void refresh(), RENDER_MS)
      try {
        timer.unref?.()
      } catch {
        /* noop */
      }
      void refresh()

      api.slots.register({
        slots: {
          app_bottom: (ctx) => {
            const s = stat()
            const theme = (ctx.theme as any)?.current
            const fg = theme
              ? s.tone === "err"
                ? theme.error
                : s.tone === "warn"
                  ? theme.warning
                  : theme.textMuted
              : FALLBACK[s.tone]
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
        } catch {
          /* bỏ qua */
        }
      }

      api.lifecycle.onDispose(() => {
        clearInterval(timer)
        dispose()
      })
    })
  } catch {
    /* im lặng */
  }
}

export default { id: "xkiro-statusline", tui } as TuiPluginModule