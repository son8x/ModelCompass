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
12. **CLI `mc`** — gói gọn mọi script thành 1 lệnh: `mc sync`, `mc publish`,
    `mc status`, `mc report`, `mc doctor` (check services local + config),
    `mc benchmark`, `mc export`, `mc help` (`modules/ModelCompass/`).
13. **Model Bank (dạng dùng chung)** — `scripts/provider/Export-ModelBank.ps1` sinh JSON
    có schema (`model-bank/schema.json`) từ production config + presets để đồng
    bộ nhiều máy / công cụ khác tiêu thụ.
14. **Provider plugin tự đóng góp** — template + recipe để thêm provider mới,
    CI validate mọi template (`configs/provider-template/`, `docs/contributing-provider.md`).
15. **GitHub Pages docs** — trang tra cứu model theo giá/tác vụ tự sinh bởi CI
    (`docs/site/`, `.github/workflows/pages.yml`).

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
│   ├── contributing-provider.md  ← recipe thêm provider mới (Phase 3.2)
│   ├── recommendations/          ← đề xuất theo nhu cầu (lập trình / luận văn / pentest)
│   └── site/                     ← GitHub Pages (Jekyll) tra cứu model theo giá/tác vụ
├── configs/
│   ├── development/opencode.jsonc  ← 🚧 soạn thử (sửa thoải mái)
│   ├── production/opencode.json    ← ✅ đã test, dùng để cài đặt
│   ├── presets/*.jsonc             ← model pick theo use case (kèm safe-minimal)
│   ├── provider-template/          ← template provider mới để đóng góp (3.2)
│   └── project-templates/          ← template per-project (code / thesis / pentest)
├── modules/ModelCompass/       ← 🧭 CLI `mc` (PowerShell module, Phase 3.1)
├── model-bank/                 ← model bank JSON + schema (dạng dùng chung, 3.3)
├── scripts/                    ← PowerShell 7, chia theo nhóm (xem bên dưới)
│   ├── mc.ps1                     ← shim CLI (giữ ở gốc)
│   ├── Common-Functions.ps1      ← hàm dùng chung (giữ ở gốc)
│   ├── config/                    ← validate / publish / install / restore / drift / sort-order
│   ├── provider/                  ← catalog / prices / usage / model bank / xKiro
│   ├── spend/                     ← ghi và tổng hợp chi phí
│   ├── env/                       ← nạp key từ .env.local vào User env
│   ├── server/                    ← opencode serve: status / start / stop / install
│   └── test/                      ← Pester suite + connectivity
├── tests/                      ← Pester: Config, SortOrder, ConfigDiff, Benchmark, StatusUpdate, SpendReport, McCli, Templates, ModelBank, DocsSite, ServerScript
├── .opencode/plugins-xkiro/    ← plugin theo dõi hạn mức xKiro (source)
│   ├── xkiro-usage.js              ← server plugin: poll /v1/usage + log/toast (mặc định bật)
│   ├── xkiro-statusline.tsx        ← TUI status bar (slot app_bottom)
│   └── xkiro-store.js              ← shared cache + file lock giữa các cửa sổ
├── reports/                    ← kết quả test (gitignored)
└── .github/workflows/          ← CI
    ├── validate.yml                ← validate config + templates + chặn API key (mỗi push/PR)
    ├── report-drift.yml            ← báo cáo drift định kỳ (cron + workflow_dispatch)
    └── pages.yml                   ← build + deploy GitHub Pages docs (3.4)
```

## 🚀 Quickstart (lần đầu — Windows, PowerShell 7)

```powershell
# 1) Kiểm tra cấu hình production hợp lệ
pwsh scripts\config\Test-ModelCompassConfig.ps1

# 2) (Tùy chọn) Ping thử connectivity của từng provider/model trong development
pwsh scripts\test\Test-ModelConnectivity.ps1 -ConfigPath configs\development\opencode.jsonc

# 3) Cài config production đang có lên opencode global (có backup tự động)
pwsh scripts\config\Install-Config.ps1
#    → Quit & restart opencode
```

**Cài từ GitHub:** `git clone https://github.com/son8x/ModelCompass.git`
rồi chạy các lệnh trên (yêu cầu **Windows + PowerShell 7**, opencode cài sẵn).
Key API **không nằm trong repo** — đọc mục **[🔐 Bảo mật](#-bảo-mật)**.

## 🔄 Vòng đời cấu hình mới (khuyến nghị)

```
1. Chỉnh sửa configs/development/opencode.jsonc      (không đụng opencode đang chạy)
2. pwsh scripts\config\Test-ModelCompassConfig.ps1 ...      (validate cú pháp)
3. pwsh scripts\test\Test-ModelConnectivity.ps1 ...       (ping provider/model)
4. Dùng thử bằng OPENCODE_CONFIG hoặc đổi model thủ công
5. pwsh scripts\config\Publish-Config.ps1 -ConnectivityTest (dev → prod, có backup)
6. git add configs/production/opencode.json && git commit  (quản lý phiên bản)
7. pwsh scripts\config\Install-Config.ps1                  (áp dụng lên opencode)
8. Restart opencode → kiểm tra → nếu lỗi: Restore-RunningConfig.ps1
```

Chi tiết: [`docs/workflow.md`](docs/workflow.md).

## 🛟 Khôi phục khi cấu hình mới gây lỗi

```powershell
pwsh scripts\config\Restore-RunningConfig.ps1 -List               # xem các backup
pwsh scripts\config\Restore-RunningConfig.ps1 -Backup opencode.json.bak-20260916-100000
```

## 🔐 Bảo mật

- Repo **KHÔNG chứa API key**. Toàn bộ key dùng cơ chế `{env:TEN_BIEN}`
  của opencode; đặt biến môi trường trên máy.
- `.env.local` (key thật) bị `.gitignore` chặn tuyệt đối — **không đặt file lộn
  xộn lên GitHub**. Mẫu an toàn `.env.sample` chỉ chứa **tên trường + placeholder
  (không có giá trị)**, được commit để làm tài liệu.
- `scripts/env/setup-opencode-env.ps1` nạp key từ `.env.local` vào môi trường User,
  tự động **chặn** nếu file key bị git theo dõi, và **che giấu key** trên màn hình:
  ```powershell
  pwsh scripts\env\setup-opencode-env.ps1 -CreateSample   # tạo .env.sample (an toàn)
  Copy-Item .env.sample .env.local                    # rồi điền giá trị thật
  pwsh scripts\env\setup-opencode-env.ps1 -FileName .env.local -Force
  ```
- CI tự quét chuỗi giống API key trong `configs/` + chặn mọi file `.env*`
  (trừ mẫu an toàn) bị theo dõi trong Git → fail nếu lộ bất cứ thứ gì.

### Bảo vệ `opencode serve` / `opencode web`

`OPENCODE_SERVER_PASSWORD` bật HTTP basic-auth cho server của opencode. Đây là
biến **tùy chọn** (không có nó thì server chạy không bảo vệ, opencode sẽ tự cảnh báo).

| Biến | Mặc định | Ý nghĩa |
|---|---|---|
| `OPENCODE_SERVER_PASSWORD` | — | mật khẩu basic-auth. Đặt → **mọi** listener của opencode đều yêu cầu auth, kể cả server do TUI spawn (TUI tự gửi credential nên vẫn chạy bình thường) |
| `OPENCODE_SERVER_USERNAME` | `opencode` | tên đăng nhập |

> Script chỉ nạp các biến có trong danh sách của nó. Nếu `.env.local` chứa tên lạ
> (gõ sai, vd `OPENCODE_SERVER_PASS`) sẽ in cảnh báo `BỎ QUA` thay vì im lặng bỏ qua.

```powershell
# nhập tay (không echo ký tự), không cần .env.local
pwsh scripts\env\setup-opencode-env.ps1 -PromptOptional

# hoặc điền vào .env.local rồi nạp cả loạt
pwsh scripts\env\setup-opencode-env.ps1 -FileName .env.local -Force

# kiểm tra (mật khẩu luôn hiện dạng ************, không lộ ký tự nào)
pwsh scripts\env\setup-opencode-env.ps1 -Check
```

Sau khi set, mở cửa sổ pwsh **mới** rồi chạy:

```powershell
opencode serve --port 4096    # hoặc: opencode web
# đăng nhập: user "opencode" / mật khẩu vừa set
```

Gỡ bỏ: `[Environment]::SetEnvironmentVariable("OPENCODE_SERVER_PASSWORD", $null, "User")`

> ⚠️ **Vì sao phải mở terminal mới?** opencode đọc `process.env` **một lần lúc khởi động**
> rồi giữ nguyên. Đổi User env mà không restart tiến trình thì server vẫn dùng mật khẩu
> cũ — triệu chứng là đăng nhập hoài thất bại dù bạn đã set đúng. `mc server` phát
> hiện đúng trường hợp này qua trạng thái `AUTH-MISMATCH`.

### 📱 Server tự chạy + truy cập từ điện thoại

Bộ script trong `scripts/server/` thay cho việc gõ `opencode serve` tay mỗi lần
khởi động máy:

| Lệnh (`mc ...`) | Script | Việc |
|---|---|---|
| `mc server` | `Get-OpenCodeServerStatus.ps1` | Trạng thái, PID, IP, URL cho điện thoại, health check |
| `mc server-start` | `Start-OpenCodeServer.ps1` | Chạy foreground + watchdog tự bật lại |
| `mc server-stop` | `Stop-OpenCodeServer.ps1` | Dừng đúng thứ tự (watchdog trước) |
| `mc server-setup` | `Install-OpenCodeServer.ps1` | Task Scheduler + firewall + `-Uninstall` |

Ba điều launcher làm khác lệnh thô:

1. **Nạp lại env từ registry User scope** — miễn nhiễm với terminal đang giữ env cũ,
   đây chính là nguyên nhân "đổi mật khẩu rồi vẫn 401".
2. **Watchdog** — Task Scheduler chỉ restart khi *fail*, mà tiến trình bị kill tay thì
   không tính là lỗi. Vòng lặp này bảo đảm server sống lại sau bất kỳ lần thoát nào.
3. **PID file** (`reports/opencode-server.pid`) — để `mc server-stop` tìm đúng tiến trình.

```powershell
# xem trạng thái + URL cần gõ trên điện thoại
mc server
# → http://10.0.20.20:4096

# cài tự chạy lúc boot (Task Scheduler, chạy bằng TÀI KHOẢN CỦA BẠN — không phải SYSTEM,
# vì opencode cần profile người dùng để đọc ~/.config/opencode, auth.json và DB)
pwsh scripts\server\Install-OpenCodeServer.ps1 -PhoneIp 192.168.1.55

# chạy cả khi chưa đăng nhập Windows (cần lưu mật khẩu Windows)
pwsh scripts\server\Install-OpenCodeServer.ps1 -PhoneIp 192.168.1.55 -RunWhenLoggedOut `
     -WindowsPassword (Read-Host -AsSecureString)

# gỡ
pwsh scripts\server\Install-OpenCodeServer.ps1 -Uninstall
```

**Về mặt an toàn:**

- Server opencode cho phép **chạy lệnh shell**. Mở `0.0.0.0` mà không mật khẩu là lộ
  quyền thực thi lệnh cho mọi thiết bị trong mạng — cả launcher và installer đều
  **từ chối chạy** trong trường hợp đó.
- Firewall **mặc định KHÔNG mở** gì cả. Chỉ mở khi bạn truyền `-PhoneIp`, và rule
  đó giới hạn theo **profile Private** + đúng IP điện thoại đó.
- Không cần `-WriteConfigBlock`: launcher nhận `--hostname/--port` từ scheduled task.
  Nếu bạn muốn ghim cổng vào `~/.config/opencode/opencode.json` cho công cụ khác đọc,
  thêm `-WriteConfigBlock` (script backup file cũ trước).
- Ra ngoài nhà: dùng **Tailscale**, đừng mở port trên router.
- Đừng mở TUI và web/Android cùng thao tác **cùng một session** — chúng dùng chung
  `opencode.db` và có thể đè lên nhau.
- IP Wi-Fi có thể đổi do DHCP; chạy `mc server` để xem lại URL hiện tại.

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
pwsh scripts\test\Test-ModelConnectivity.ps1 -Benchmark -Provider '1-xkiro-free' -Model 'minimax/minimax-m3:free'

# Kèm report Markdown vào reports\
pwsh scripts\test\Test-ModelConnectivity.ps1 -Benchmark -Provider '1-xkiro-free' -Report
```

`-Benchmark` **bắt buộc** thu hẹp bằng `-Provider` hoặc `-Model` để không đốt
quota khi chạy cả catalog.

## 🧭 ModelCompass CLI (`mc`)

Gói gọn mọi script thành 1 lệnh — module PowerShell tại `modules/ModelCompass/`,
gọi script qua tiến trình pwsh con (an toàn khi script có `exit`):

```powershell
& scripts\mc.ps1 help                       # liệt kê lệnh
& scripts\mc.ps1 status                     # validate production + so dev/prod
& scripts\mc.ps1 doctor                     # check env + services local + config
& scripts\mc.ps1 publish                    # dev → prod (kèm backup)
& scripts\mc.ps1 report -Month 2026-09      # spend report
& scripts\mc.ps1 export                     # sinh model-bank/modelbank.json
& scripts\mc.ps1 sync                       # kéo catalog provider (mạng)
& scripts\mc.ps1 server                     # trạng thái server + URL cho điện thoại
& scripts\mc.ps1 server-setup               # cài tự chạy lúc boot (cần PowerShell Admin)
```

Có thể import trực tiếp để gõ `mc` không cần `scripts\mc.ps1`:
thêm vào `$PROFILE` dòng `Import-Module <repo>\modules\ModelCompass\ModelCompass.psd1`.

Import trực tiếp trong PowerShell: `Import-Module modules\ModelCompass\ModelCompass.psd1`,
rồi dùng `mc <lệnh>`. `mc doctor` cần các env `XTROUTER_API_KEY`, `OMNIROUTE_KEY`,
`TEAMO_API_KEY`, `NINE_ROUTER_API_KEY` và 2 service local OmniRoute/9Router nếu muốn để ý.

## 🗂 Model bank & GitHub Pages docs

- **Model bank**: `scripts/provider/Export-ModelBank.ps1` đọc `configs/production/opencode.json`
  + `configs/presets/*` + catalog live → `model-bank/modelbank.json` (schema
  `model-bank/schema.json`). Chứa providers, models (giá từ `name` + catalog, tag
  `preset:<tên>`), presets, stats — để công cụ khác/dâ chuyển đồng bộ dùng.
- **Docs site (GitHub Pages)**: `docs/site/` build tự động bởi `.github/workflows/pages.yml`
  — sinh model bank vào `_data/`, Jekyll render bảng tra cứu model theo giá/tác vụ.
  Bật `Settings → Pages → Source = GitHub Actions` là trang chạy.

## 📄 Giấy phép

[MIT](LICENSE) — tự do dùng, sửa, chia sẻ với điều kiện giữ phần thông báo
bản quyền.

---

*Powered by ModelCompass — tìm đúng model, chạy đúng cấu hình.*