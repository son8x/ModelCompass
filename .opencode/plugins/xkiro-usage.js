// ═══════════════════════════════════════════════════════════════════════════
//  xkiro-usage — plugin opencode theo dõi hạn mức tài khoản xKiro
// ═══════════════════════════════════════════════════════════════════════════
//  - Chạy trong tiến trình opencode sẵn có (KHÔNG spawn thêm tiến trình).
//  - Gọi GET /v1/usage của xKiro (miễn phí, không tốn token) định kỳ.
//  - Ghi 1 dòng tóm tắt vào opencode.log (mở bằng `:open-logs`).
//  - HIỂN THỊ: status bar cuối màn hình do xkiro-statusline.tsx đảm nhiệm
//    (xem .opencode/plugins/xkiro-statusline.tsx). Tùy chọn ghi thêm dòng
//    vào transcript chat qua XKIRO_USAGE_INJECT=1 (phương pháp opencode-quota).
//  - Bắn toast cảnh báo khi free-token / budget paid / burst chạm ngưỡng
//    (kèm toast trạng thái theo chu kỳ nếu bật).
//  - Key đọc từ biến môi trường XTROUTER_API_KEY — KHÔNG in key, KHÔNG lưu key.
//
//  Biến môi trường điều khiển:
//    XKIRO_USAGE_DISABLE=1        tắt plugin
//    XKIRO_USAGE_INTERVAL=300     chu kỳ poll nền (giây)
//    XKIRO_USAGE_WARN_PCT=90      ngưỡng tỉ lệ để bật toast cảnh báo
//    XKIRO_USAGE_TOAST_EACH=1     toast trạng thái sau mỗi session.idle (0=tắt)
//    XKIRO_USAGE_TOAST_GAP=60     khoảng tối thiểu giữa 2 toast (giây)
//    XKIRO_USAGE_INJECT=1         bật ghi trạng thái vào transcript chat (mặc định tắt)
//    XKIRO_USAGE_INJECT_GAP=300   khoảng tối thiểu giữa 2 lần ghi transcript (giây)
// ═══════════════════════════════════════════════════════════════════════════

const USAGE_URL = "https://api.xkiro.com/v1/usage"

const DISABLED =
  process.env.XKIRO_USAGE_DISABLE === "1" ||
  process.env.XKIRO_USAGE_DISABLE === "true"
const INTERVAL_MS =
  (Number(process.env.XKIRO_USAGE_INTERVAL) || 300) * 1000
const WARN_PCT = Number(process.env.XKIRO_USAGE_WARN_PCT) || 90
const TOAST_EACH =
  process.env.XKIRO_USAGE_TOAST_EACH !== "0" &&
  process.env.XKIRO_USAGE_TOAST_EACH !== "false"
const TOAST_GAP_MS = (Number(process.env.XKIRO_USAGE_TOAST_GAP) || 60) * 1000
const INJECT_GAP_MS = (Number(process.env.XKIRO_USAGE_INJECT_GAP) || 300) * 1000
const INJECT_ENABLED =
  process.env.XKIRO_USAGE_INJECT === "1" ||
  process.env.XKIRO_USAGE_INJECT === "true"

function fmtCount(n) {
  const v = Number(n ?? 0)
  if (v >= 1e9) return `${(v / 1e9).toFixed(2)}B`
  if (v >= 1e6) return `${(v / 1e6).toFixed(2)}M`
  if (v >= 1e3) return `${(v / 1e3).toFixed(1)}K`
  return String(Math.round(v))
}

function fmtUsd(v) {
  try {
    return `$${Number(v).toFixed(2)}`
  } catch {
    return "$0.00"
  }
}

export const xkiroUsagePlugin = async ({ client }) => {
  if (DISABLED) return {}

  const warned = { free: false, burst: false, budget: false }
  const firstToast = { done: false }

  async function fetchUsage() {
    const key =
      process.env.XTROUTER_API_KEY ||
      process.env.XKIRO_API_KEY
    if (!key) return null
    try {
      const res = await fetch(USAGE_URL, {
        headers: { Authorization: `Bearer ${key}`, "x-api-key": key },
      })
      if (!res.ok) return null
      return await res.json()
    } catch {
      return null
    }
  }

  async function toast(message, variant = "info", durationMs = 7000) {
    try {
      await Promise.race([
        client.tui.showToast({
          body: { message, variant, duration: durationMs },
        }),
        new Promise((r) => setTimeout(r, 2500)),
      ])
      await logLine(`toast đã gửi [${variant}]`, "info")
    } catch (e) {
      await logLine(`toast KHÔNG gửi được: ${e?.message ?? e}`, "warn")
    }
  }

  async function logLine(message, level = "info") {
    try {
      await client.app.log({
        body: { service: "xkiro-usage", level, message },
      })
    } catch {
      // log panel không mở — không phải lỗi
    }
  }

  // Ghi trạng thái vào transcript chat (tùy chọn, XKIRO_USAGE_INJECT=1).
  // noReply=true  → không trigger AI trả lời.
  // ignored=true  → phần tử KHÔNG được đưa vào prompt context (0 token).
  async function injectStatus(sessionID, text) {
    if (!INJECT_ENABLED) return
    if (!sessionID || !text) return
    if (Date.now() - lastInjectedAt < INJECT_GAP_MS) return
    try {
      lastInjectedAt = Date.now()
      await client.session.prompt({
        path: { id: sessionID },
        body: {
          noReply: true,
          parts: [{ type: "text", text: `\`${text}\``, ignored: true }],
        },
      })
      await logLine(`transcript OK sid=${sessionID}`, "info")
    } catch (e) {
      await logLine(`transcript LỖI sid=${sessionID}: ${e?.message ?? e}`, "warn")
    }
  }

  function summarize(data) {
    const ft = data.free_tokens || {}
    const limits = {
      free: { cap: Number(ft.limit_per_day) || 0, rem: Number(ft.remaining) || 0 },
      burst: {},
      budget: {},
      wallet: data.wallet ? Number(data.wallet.balance_usd) || 0 : null,
    }
    for (const w of data.windows || []) {
      const key = w.kind === "short" ? "burst" : "budget"
      limits[key] = {
        cap: Number(w.cap_usd) || 0,
        rem: Number(w.remaining_usd) || 0,
        spent: Number(w.spent_usd) || 0,
      }
    }

    const parts = []
    const usedPct = (cap, rem) => (cap > 0 ? (1 - rem / cap) * 100 : 0)
    if (limits.free.cap) {
      parts.push(`free còn ${fmtCount(limits.free.rem)} (đã dùng ${usedPct(limits.free.cap, limits.free.rem).toFixed(1)}%)`)
    }
    if (limits.budget.cap) {
      parts.push(`budget còn ${fmtUsd(limits.budget.rem)}/${fmtUsd(limits.budget.cap)} (đã dùng ${usedPct(limits.budget.cap, limits.budget.rem).toFixed(1)}%)`)
    }
    if (limits.burst.cap) {
      parts.push(`burst còn ${fmtUsd(limits.burst.rem)}/${fmtUsd(limits.burst.cap)} (đã dùng ${usedPct(limits.burst.cap, limits.burst.rem).toFixed(1)}%)`)
    }
    parts.push(`wallet ${fmtUsd(limits.wallet ?? 0)}`)
    return { text: `xKiro | ${parts.join(" | ")}`, limits }
  }

  async function poll(showToast = false) {
    const data = await fetchUsage()
    if (!data) {
      await logLine("xKiro | /v1/usage không đọc được (network/quota)", "warn")
      return
    }
    const { text, limits } = summarize(data)
    await logLine(text)
    if (showToast && !firstToast.done) {
      firstToast.done = true
      await toast(text)
    }

    const pct = (cap, rem) => (cap > 0 ? (1 - rem / cap) * 100 : 0)

    const checks = [
      { name: "free", lim: limits.free, pct: pct(limits.free.cap, limits.free.rem) },
      { name: "burst", lim: limits.burst, pct: pct(limits.burst.cap, limits.burst.rem) },
      { name: "budget", lim: limits.budget, pct: pct(limits.budget.cap, limits.budget.rem) },
    ]
    for (const c of checks) {
      const near = c.pct >= WARN_PCT
      if (near && !warned[c.name]) {
        warned[c.name] = true
        const variant = c.pct >= 100 ? "error" : c.pct >= WARN_PCT ? "warning" : "info"
        await toast(`xKiro: ${c.name} đã dùng ${c.pct.toFixed(1)}% — còn ${fmtCount(c.lim.rem)}`, variant)
      }
      if (!near) warned[c.name] = false
    }
  }

  setTimeout(() => void poll(), 0)
  const timer = setInterval(() => void poll(), INTERVAL_MS)
  timer.unref?.()

  let lastToastAt = 0
  let lastInjectedAt = 0
  const subagentIDs = new Set()

  return {
    event: async ({ event }) => {
      const t = event.type
      const props = event.properties ?? {}

      if (t === "session.created" && props.info) {
        if (props.info.parentID) subagentIDs.add(props.info.id)
        else subagentIDs.delete(props.info.id)
        if (!props.info.parentID && props.info.id) {
          const data = await fetchUsage()
          if (data) await injectStatus(props.info.id, summarize(data).text)
        }
      }

      if (t === "session.idle") {
        const sid = props.sessionID
        await poll()
        if (sid && !subagentIDs.has(sid)) {
          const data = await fetchUsage()
          if (data) {
            await injectStatus(sid, summarize(data).text)
            if (TOAST_EACH && Date.now() - lastToastAt >= TOAST_GAP_MS) {
              lastToastAt = Date.now()
              void toast(summarize(data).text, "info", 6000)
            }
          }
        }
      }

      if (t === "server.connected") {
        await poll(true)
      }
    },
  }
}