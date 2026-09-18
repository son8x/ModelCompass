# 🧭 ModelCompass

Dự án **phân tích, đánh giá và quản lý cấu hình AI provider/model** cho
[opencode](https://opencode.ai) — trải rộng từ **miễn phí** đến **trả phí**,
kèm theo quy trình **an toàn** để đưa model mới vào sử dụng mà **không làm hỏng
opencode đang chạy**.

[![CI — validate config](https://github.com/son8x/ModelCompass/actions/workflows/validate.yml/badge.svg)](https://github.com/son8x/ModelCompass/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 🎯 Mục tiêu: biết **dùng provider/model nào** cho từng nhu cầu (lập trình,
> viết luận văn, pentest, …), và **cấu hình opencode nhanh nhất** với cấu hình
> được **quản lý phiên bản trong Git/GitHub**.

---

## ✨ Tính năng

1. **Phân tích provider & model** — bảng giá API (input/output per 1M token),
   model free/paid, tốc độ, thế mạnh theo từng tác vụ → xem `docs/providers-and-models.md`.
2. **Đề xuất theo nhu cầu** — chọn nhanh model phù hợp:
   `docs/recommendations/*.md` (lập trình, viết luận văn, pentest).
3. **Cấu hình opencode nhanh nhất** — Các preset "model pick" trong
   `configs/presets/*.jsonc`, dán vào config development rồi publish.
4. **Quản lý phiên bản GitHub** — `git init` sẵn, CI validate cấu hình mỗi khi
   PR/push vào `configs/`, block API key lọt vào repo.
5. **Quy trình 2 giai đoạn an toàn** — `development/` (soạn thử) → `production/`
   (đã test) → `~/.config/opencode/` (đang chạy), kèm backup/rollback.
6. **Plugin theo dõi hạn mức xKiro** — poll `GET /v1/usage` ngay trong opencode:
   log + toast cảnh báo + status bar (`xkiro-usage.js`, `xkiro-statusline.tsx`).
7. **Chế độ an toàn (safe-mode)** — preset chỉ dùng provider/model có trong
   catalog live + cần đúng 1 API key, để dev khởi động nhanh mà không tìm hiểu
   trước (`configs/presets/safe-minimal.jsonc`).
8. **Cấu hình theo từng dự án** — template per-project + cách dùng
   `OPENCODE_CONFIG`/`OPENCODE_CONFIG_CONTENT` (`configs/project-templates/`,
   `docs/per-project-config.md`).
9. **Helper sort-order** — `New-SortOrderKey.ps1` sinh/tìm key `yyyy-MM-dd` cho
   mục `sortOrder` của provider/model (không đụng file), tránh trùng key.
10. **Báo cáo drift định kỳ** — CI tự validate dev/prod/presets, ghi report, mở
    issue khi có vấn đề (`report-drift.yml`).
11. **Benchmark latency/token** — `Test-ModelConnectivity.ps1 -Benchmark` gọi
    N lần mỗi model, tổng hợp median ms + tokens/giây.

---

## 📁 Cấu trúc

```
01-ModelCompass/
├── README.md                  ← bạn đang ở đây
├── LICENSE                    ← MIT
├── docs/
│   ├── providers-and-models.md   ← phân tích chi tiết provider/model
│   ├── workflow.md               ← quy trình development → production → release
│   ├── per-project-config.md     ← cấu hình theo từng dự án (OPENCODE_CONFIG)
│   └── recommendations/          ← đề xuất theo nhu cầu (lập trình / luận văn / pentest)
├── configs/
│   ├── development/opencode.jsonc  ← 🚧 soạn thử (sửa thoải mái)
│   ├── production/opencode.json    ← ✅ đã test, dùng để cài đặt
│   ├── presets/*.jsonc             ← model pick theo use case (kèm safe-minimal)
│   └── project-templates/          ← template per-project (code / thesis / pentest)
├── scripts/                    ← PowerShell 7: validate / test / publish / install / restore / report* / New-SortOrderKey
├── tests/                      ← Pester: Config, SortOrder, ConfigDiff, Benchmark, StatusUpdate, SpendReport
├── .opencode/plugins-xkiro/    ← plugin theo dõi hạn mức xKiro (source)
│   ├── xkiro-usage.js              ← server plugin: poll /v1/usage + log/toast (mặc định bật)
│   ├── xkiro-statusline.tsx        ← TUI status bar (slot app_bottom)
│   └── xkiro-store.js              ← shared cache + file lock giữa các cửa sổ
├── reports/                    ← kết quả test (gitignored)
└── .github/workflows/          ← CI
    ├── validate.yml                ← validate config + chặn API key (mỗi push/PR)
    └── report-drift.yml            ← báo cáo drift định kỳ (cron + workflow_dispatch)
```

## 🚀 Quickstart (lần đầu — Windows, PowerShell 7)

```powershell
# 1) Kiểm tra cấu hình production hợp lệ
pwsh scripts\Test-ModelCompassConfig.ps1

# 2) (Tùy chọn) Ping thử connectivity của từng provider/model trong development
pwsh scripts\Test-ModelConnectivity.ps1 -ConfigPath configs\development\opencode.jsonc

# 3) Cài config production đang có lên opencode global (có backup tự động)
pwsh scripts\Install-Config.ps1
#    → Quit & restart opencode
```

**Cài từ GitHub:** `git clone https://github.com/son8x/ModelCompass.git`
rồi chạy các lệnh trên (yêu cầu **Windows + PowerShell 7**, opencode cài sẵn).
Key API **không nằm trong repo** — đọc mục **[🔐 Bảo mật](#-bảo-mật)**.

## 🔄 Vòng đời cấu hình mới (khuyến nghị)

```
1. Chỉnh sửa configs/development/opencode.jsonc      (không đụng opencode đang chạy)
2. pwsh scripts\Test-ModelCompassConfig.ps1 ...      (validate cú pháp)
3. pwsh scripts\Test-ModelConnectivity.ps1 ...       (ping provider/model)
4. Dùng thử bằng OPENCODE_CONFIG hoặc đổi model thủ công
5. pwsh scripts\Publish-Config.ps1 -ConnectivityTest (dev → prod, có backup)
6. git add configs/production/opencode.json && git commit  (quản lý phiên bản)
7. pwsh scripts\Install-Config.ps1                  (áp dụng lên opencode)
8. Restart opencode → kiểm tra → nếu lỗi: Restore-RunningConfig.ps1
```

Chi tiết: [`docs/workflow.md`](docs/workflow.md).

## 🛟 Khôi phục khi cấu hình mới gây lỗi

```powershell
pwsh scripts\Restore-RunningConfig.ps1 -List               # xem các backup
pwsh scripts\Restore-RunningConfig.ps1 -Backup opencode.json.bak-20260916-100000
```

## 🔐 Bảo mật

- Repo **KHÔNG chứa API key**. Toàn bộ key dùng cơ chế `{env:TEN_BIEN}`
  của opencode; đặt biến môi trường trên máy.
- `.env.local` (key thật) bị `.gitignore` chặn tuyệt đối — **không đặt file lộn
  xộn lên GitHub**. Mẫu an toàn `.env.sample` chỉ chứa **tên trường + placeholder
  (không có giá trị)**, được commit để làm tài liệu.
- `scripts/setup-opencode-env.ps1` nạp key từ `.env.local` vào môi trường User,
  tự động **chặn** nếu file key bị git theo dõi, và **che giấu key** trên màn hình:
  ```powershell
  pwsh scripts\setup-opencode-env.ps1 -CreateSample   # tạo .env.sample (an toàn)
  Copy-Item .env.sample .env.local                    # rồi điền giá trị thật
  pwsh scripts\setup-opencode-env.ps1 -FileName .env.local -Force
  ```
- CI tự quét chuỗi giống API key trong `configs/` + chặn mọi file `.env*`
  (trừ mẫu an toàn) bị theo dõi trong Git → fail nếu lộ bất cứ thứ gì.

## 🧩 Plugin: theo dõi hạn mức xKiro

Theo dõi hạn mức tài khoản xKiro ngay trong opencode — **chỉ đọc**, không tốn
token, gọi `GET https://api.xkiro.com/v1/usage` (endpoint miễn phí). Bộ nguồn
nằm trong `.opencode/plugins-xkiro/`:

| File | Loại | Vai trò |
|---|---|---|
| `xkiro-usage.js` | Server plugin | Poll hạn mức định kỳ (riêng xKiro), ghi chuỗi `xKiro · free … · burst … · budget …` vào `opencode.log`, toast cảnh báo khi vượt ngưỡng |
| `xkiro-statusline.tsx` | TUI plugin (slot `app_bottom`) | Status bar **multi-provider quota** (đọc `QUOTA_PROVIDERS`); xKiro hiển thị free/burst/budget/wallet; provider khác hiện "chưa có quota API" nếu endpoint chưa hỗ trợ; vàng ≥90%, đỏ khi hết |
| `xkiro-store.js` | Module dùng chung | Cache + file lock để **mọi cửa sổ opencode** dùng chung 1 số liệu, chỉ 1 tiến trình gọi mạng |
| `quota-common.js` | Module dùng chung (Phase 1.4) | Tách logic: danh sách provider (`QUOTA_PROVIDERS`), cache dir, tạo store per-provider, format hiển thị xKiro — dùng bởi statusline, có thể mở rộng cho usage plugin sau này |

**Cài đặt** (script `Install-Config.ps1` đã sao 3 file vào `~/.config/opencode/lib/`):
đăng ký trong mảng `plugin` của `opencode.json` global:

```json
"plugin": [
  "./lib/xkiro-usage.js",
  "./lib/xkiro-statusline.tsx"
]
```

**Cấu hình** qua biến môi trường:

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `XKIRO_USAGE_INTERVAL` | 300 | chu kỳ poll (giây) |
| `XKIRO_USAGE_WARN_PCT` | 90 | % hạn mức dùng để cảnh báo (statusline & toast) |
| `XKIRO_USAGE_TOAST_EACH` / `XKIRO_USAGE_TOAST_GAP` | 1 / 60 | toast lặp lại mỗi N lần / cách N giây |
| `XKIRO_USAGE_INJECT` / `XKIRO_USAGE_INJECT_GAP` | 0 / 300 | ghi thêm hạn mức vào transcript chat |
| `XKIRO_STATUSBAR_RENDER_MS` | 5000 | tần suất render status bar |
| `XKIRO_USAGE_TTL` | 60 | TTL cache dùng chung (giây) |
| `XKIRO_USAGE_CACHE_DIR` | `~/.cache/xkiro` | nơi lưu `usage.json` |
| `XKIRO_USAGE_DISABLE` / `XKIRO_STATUSBAR_DISABLE` | — | tắt server plugin / status bar |
| `QUOTA_PROVIDERS` | `xkiro` | danh sách provider hiển thị trên status bar (cách nhau dấu phẩy, vd `xkiro,teamo`) |
| `QUOTA_STATUSBAR_DISABLE` / `QUOTA_STATUSBAR_RENDER_MS` / `QUOTA_STATUSBAR_WARN_PCT` | — / 5000 / 90 | tương đương `XKIRO_STATUSBAR_*`, ưu tiên đọc trước (status bar) |
| `QUOTA_CACHE_DIR` | `~/.cache/quota` | cache dir cho provider ngoài xKiro (xKiro vẫn dùng `XKIRO_USAGE_CACHE_DIR` / `~/.cache/xkiro`) |

**Bảo mật:** plugin chỉ đọc endpoint `/v1/usage` (miễn phí) — **không** in hay lưu
`XTROUTER_API_KEY`; key chỉ được đọc từ biến môi trường khi gọi model.

## 📊 Nguồn dữ liệu giá

Bảng giá token là **ảnh chụp tại thời điểm viết** (Q4/2026), có ghi nguồn trong
`docs/providers-and-models.md`. Giá nhà cung cấp thay đổi thường xuyên — trước
khi quyết định trả phí, hãy xác nhận lại trên trang chính thức của provider.

## 📏 Đo tốc độ model (benchmark)

```powershell
# Benchmark 1 model (mặc định 6 lượt gọi, tổng hợp median ms + tokens/giây)
pwsh scripts\Test-ModelConnectivity.ps1 -Benchmark -Provider '1-xkiro-free' -Model 'minimax/minimax-m3:free'

# Kèm report Markdown vào reports\
pwsh scripts\Test-ModelConnectivity.ps1 -Benchmark -Provider '1-xkiro-free' -Report
```

`-Benchmark` **bắt buộc** thu hẹp bằng `-Provider` hoặc `-Model` để không đốt
quota khi chạy cả catalog.

## 📄 Giấy phép

[MIT](LICENSE) — tự do dùng, sửa, chia sẻ với điều kiện giữ phần thông báo
bản quyền.

---

*Powered by ModelCompass — tìm đúng model, chạy đúng cấu hình.*