// xkiro-store.js — bộ nhớ hạn mức xKiro dùng chung giữa MỌI tiến trình opencode.
//
// Mục tiêu: nhiều cửa sổ / nhiều project cùng hiển thị 1 giá trị, nhưng chỉ
// 1 TIẾN TRÌNH duy nhất gọi GET /v1/usage; các tiến trình còn lại chỉ đọc
// file cache nội bộ (không đụng mạng) miễn cache còn tươi.
//
// Cơ chế:
//   - cache file: <dir>/usage.json  { fetchedAt, data }  (ghi atomic: tmp + rename)
//   - lock file : <dir>/usage.lock  (tạo bằng openSync 'wx' = nguyên tử)
//   - resolve(loader):
//       * cache tươi (age < ttlMs)   → đọc cache, KHÔNG gọi loader (0 mạng)
//       * cache cũ + giành được lock → gọi loader, ghi cache, nhả lock
//       * cache cũ + không giành lock → trả cache cũ (kẻ khác đang fetch)
//   - lock quá già (lockStaleMs, chủ cũ crash) → chiếm lại được.
//
// Environment (đọc theo cùng chuẩn ở cả TUI lẫn server plugin):
//   XKIRO_USAGE_CACHE_DIR   thư mục cache tự chọn
//   XKIRO_USAGE_TTL         TTL cache (giây, mặc định 60)

import {
  closeSync,
  mkdirSync,
  openSync,
  readFileSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "node:fs"
import { join } from "node:path"

function env(name) {
  try {
    return globalThis.process?.env?.[name]
  } catch {
    return undefined
  }
}

export function cacheDir() {
  const override = env("XKIRO_USAGE_CACHE_DIR")
  if (override) return override
  const home = env("USERPROFILE") || env("HOME") || env("LOCALAPPDATA") || "."
  const base = env("XDG_CACHE_HOME") || join(home, ".cache")
  return join(base, "xkiro")
}

export function createUsageStore(options = {}) {
  const dir = options.dir || cacheDir()
  const ttlMs = options.ttlMs || (Number(env("XKIRO_USAGE_TTL")) || 60) * 1000
  const lockStaleMs = options.lockStaleMs || 120_000
  const cacheFile = join(dir, "usage.json")
  const lockFile = join(dir, "usage.lock")

  function get() {
    try {
      const obj = JSON.parse(readFileSync(cacheFile, "utf8"))
      if (!obj || typeof obj.fetchedAt !== "number" || !obj.data) return null
      return obj
    } catch {
      return null
    }
  }

  function write({ data }) {
    try {
      mkdirSync(dir, { recursive: true })
      const payload = JSON.stringify({ fetchedAt: Date.now(), data })
      const tmp = `${cacheFile}.${process.pid}.tmp`
      writeFileSync(tmp, payload, "utf8")
      try {
        renameSync(tmp, cacheFile)
      } catch {
        writeFileSync(cacheFile, payload, "utf8")
      }
      return true
    } catch {
      return false
    }
  }

  let owned = false

  function lock() {
    if (owned) return true
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        mkdirSync(dir, { recursive: true })
        const fd = openSync(lockFile, "wx")
        try {
          writeFileSync(fd, `${process.pid} ${new Date().toISOString()}`)
        } catch {
          /* không quan trọng */
        }
        closeSync(fd)
        owned = true
        return true
      } catch (e) {
        if (e?.code !== "EEXIST") return false
        try {
          const st = statSync(lockFile)
          if (Date.now() - st.mtimeMs > lockStaleMs) {
            try {
              unlinkSync(lockFile)
            } catch {
              /* ai đó đã xóa */
            }
            continue
          }
        } catch {
          try {
            unlinkSync(lockFile)
          } catch {
            /* ai đó đã xóa */
          }
        }
        return false
      }
    }
    return false
  }

  function unlock() {
    if (!owned) return
    owned = false
    try {
      unlinkSync(lockFile)
    } catch {
      /* ai đó đã xóa */
    }
  }

  async function resolve(loader) {
    const cached = get()
    if (cached && Date.now() - cached.fetchedAt < ttlMs) {
      return { data: cached.data, fetchedAt: cached.fetchedAt, from: "cache" }
    }
    if (!lock()) {
      return { data: cached?.data ?? null, fetchedAt: cached?.fetchedAt ?? 0, from: "locked" }
    }
    try {
      const data = await loader()
      if (data) {
        write({ data })
        return { data, fetchedAt: Date.now(), from: "fetch" }
      }
      return { data: cached?.data ?? null, fetchedAt: cached?.fetchedAt ?? 0, from: "failed" }
    } finally {
      unlock()
    }
  }

  return { get, write, lock, unlock, resolve, dir, cacheFile }
}