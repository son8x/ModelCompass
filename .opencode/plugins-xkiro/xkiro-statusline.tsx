// quota-statusline — status bar (slot app_bottom) hiển thị hạn mức ĐA PROVIDER
//
// Phase 1.4: tổng quát hoá từ xkiro-statusline → "quota bar":
//   - Đọc danh sách provider từ env QUOTA_PROVIDERS (mặc định "xkiro").
//   - Mỗi provider có 1 shared store (quota-common.js → xkiro-store.js); chỉ 1
//     tiến trình gọi mạng/lock, các cửa sổ khác đọc cache nội bộ.
//   - Provider chưa có API quota (teamo/openrouter/…) → ghi ngắn "chưa có quota
//     API" chứ không vỡ (fallback).
//   - Giữ nguyên tương thích env cũ: XKIRO_STATUSBAR_DISABLE,
//     XKIRO_STATUSBAR_RENDER_MS, XKIRO_USAGE_WARN_PCT.
//
/** @jsxImportSource @opentui/solid */
import { createRoot, createSignal } from "solid-js"
import type { TuiPlugin, TuiPluginModule } from "@opencode-ai/plugin/tui"
import {
  activeProviders,
  createQuotaStore,
  QUOTA_URLS,
  summarizeXKiro,
  xkiroKey,
} from "./quota-common.js"

function env(name: string): string | undefined {
  try {
    return (globalThis as any).process?.env?.[name] as string | undefined
  } catch {
    return undefined
  }
}

const DISABLED =
  env("QUOTA_STATUSBAR_DISABLE") === "1" ||
  env("QUOTA_STATUSBAR_DISABLE") === "true" ||
  env("XKIRO_STATUSBAR_DISABLE") === "1" ||
  env("XKIRO_STATUSBAR_DISABLE") === "true"
const RENDER_MS =
  (Number(env("QUOTA_STATUSBAR_RENDER_MS")) ||
    Number(env("XKIRO_STATUSBAR_RENDER_MS")) ||
    5000) as number
const WARN_PCT =
  Number(env("QUOTA_STATUSBAR_WARN_PCT")) ||
  Number(env("XKIRO_STATUSBAR_WARN_PCT")) ||
  Number(env("XKIRO_USAGE_WARN_PCT")) ||
  90

const FALLBACK_TONE: Record<"ok" | "warn" | "err", string> = {
  ok: "white",
  warn: "yellow",
  err: "red",
}
const RANK: Record<"ok" | "warn" | "err", number> = { ok: 0, warn: 1, err: 2 }

type Tone = "ok" | "warn" | "err"
type Segment = { provider: string; text: string; tone: Tone }

async function refreshProvider(name: string): Promise<Segment> {
  if (name === "xkiro") {
    const key = xkiroKey()
    if (!key) return { provider: name, text: `xKiro · thiếu key`, tone: "warn" }
    try {
      const res = await fetch(QUOTA_URLS.xkiro, {
        headers: { Authorization: `Bearer ${key}`, "x-api-key": key },
      })
      if (!res.ok) return { provider: name, text: `xKiro · lỗi ${res.status}`, tone: "warn" }
      const data = await res.json()
      const segs: Segment[] = []
      try {
        const store = createQuotaStore(name)
        const stored = await store.resolve(async () => data)
        segs.push({ provider: name, ...summarizeXKiro(stored.data ?? data, WARN_PCT) })
      } catch {
        segs.push({ provider: name, ...summarizeXKiro(data, WARN_PCT) })
      }
      return segs[0]
    } catch {
      return { provider: name, text: `xKiro · không đọc được`, tone: "warn" }
    }
  }
  // Chưa có endpoint quota cho provider này — fallback, không hiển thị dữ liệu.
  return { provider: name, text: `${name} · chưa có quota API`, tone: "ok" }
}

const tui: TuiPlugin = async (api, _options, _meta) => {
  if (DISABLED) return

  try {
    createRoot((dispose) => {
      const [segments, setSegments] = createSignal<Segment[]>([])
      const providers = activeProviders()

      // Nạp cache tươi ngay nếu có (không gọi mạng).
      void (async () => {
        for (const name of providers) {
          try {
            const cache = createQuotaStore(name).get?.()
            if (cache?.data) setSegments((prev) => [...prev, { provider: name, ...summarizeXKiro(cache.data, WARN_PCT) }])
          } catch {
            /* cache không có — refresh thật sau */
          }
        }
      })()

      async function refreshAll() {
        for (const name of providers) {
          const seg = await refreshProvider(name)
          setSegments((prev) => [...prev.filter((s) => s.provider !== name), seg])
        }
      }

      const timer = setInterval(() => void refreshAll(), RENDER_MS)
      try {
        timer.unref?.()
      } catch {
        /* noop */
      }
      void refreshAll()

      api.slots.register({
        slots: {
          app_bottom: (ctx) => {
            const segs = segments()
            const line =
              segs.length === 0
                ? "quota · đang đồng bộ..."
                : "quota · " + segs.map((s) => s.text).join(" · ")
            let worst: Tone = "ok"
            for (const s of segs) if (RANK[s.tone] > RANK[worst]) worst = s.tone
            const theme = (ctx.theme as any)?.current
            const fg = theme
              ? worst === "err"
                ? theme.error
                : worst === "warn"
                  ? theme.warning
                  : theme.textMuted
              : FALLBACK_TONE[worst]
            return (
              <box paddingLeft={1} paddingRight={1} height={1}>
                <text style={{ fg } as never}>{line}</text>
              </box>
            )
          },
        },
      })

      for (const evt of ["session.created", "session.idle"] as const) {
        try {
          api.event.on(evt, () => void refreshAll())
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