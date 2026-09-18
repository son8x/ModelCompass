# Changelog

Tạo theo chuẩn [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) +
[Semantic Versioning](https://semver.org/). Mỗi release = một mốc cấu hình hoặc
bộ nâng cấp quy trình được "đóng gói" và commit lên GitHub.

## [0.6.0] — 2026-09-18 — Phase 3 hoàn tất (3.1–3.4)

### Thêm
- **3.1 ModelCompass CLI (`mc`)**: module PowerShell `modules/ModelCompass/`
  (`ModelCompass.psd1` + `.psm1`, chỉ export `mc`) — map 17 lệnh (`sync`, `publish`,
  `status`, `report`, `doctor`, `benchmark`, `export`, `help`, …), gọi script qua tiến
  trình pwsh con (script `exit` không giết phiên opencode), `doctor` = check env bắt
  buộc + TCP local services OmniRoute/9Router + validate production, `status` = validate
  + so dev/prod, `benchmark` tự thêm `-Benchmark`; `ConvertTo-McCommandLine` giữ cờ,
  bọc/escape giá trị an toàn. Shim `scripts/mc.ps1`. `tests/McCli.Tests.ps1` (11 test).
- **3.2 Provider recipe cho người tự đóng góp**: `configs/provider-template/opencode.json`
  (provider mẫu khai báo `provider.<id>`, `options.apiKey` = `{env:VAR}`, `models` có
  `sortOrder`/`release_date`, ghi chú tiếng Việt trong `readme` model) + `docs/contributing-provider.md`
  (quy ước tên id, ánh xạ catalog, recipe 7 bước, checklist CI). CI `validate.yml` thêm
  step validate **mọi template** (project-templates + provider-template). `tests/Templates.Tests.ps1` (6 test).
- **3.3 Model Bank**: `scripts/Export-ModelBank.ps1` (`Get-PricesFromName`, `Get-ModelBankPricing`
  — giá ưu tiên catalog live, fallback giá trong `name`, tôn trọng strip tiền tố id gateway;
  `New-ModelBank` — providers, models kèm pricing/catalogPricing/tags `preset:<tên>`, presets,
  stats: modelCount/free/paid/tagSet, version 1.0.0) + `model-bank/schema.json` (JSON Schema
  2020-12) + **artifact `model-bank/modelbank.json`** (6 provider · 80 model · 5 preset — hàm
  xKiro 0 giá nhồi nhưng có catalog). `tests/ModelBank.Tests.ps1` (12 test).
- **3.4 GitHub Pages docs**: `docs/site/` (Jekyll theme minima: `index.md` tra cứu
  provider + presets, `models.md` bảng model giá/tác vụ — đọc `_data/modelbank.json` qua
  `site.data.modelbank`) + `.github/workflows/pages.yml` (sinh model bank → `jekyll-build-pages`
  → upload → deploy; bật Pages source = GitHub Actions). `tests/DocsSite.Tests.ps1` (4 test).

### Changed
- `scripts/Export-ModelBank.ps1`: đường dẫn preset/source config xuất ra là **tương đối**
  repo (đồng bộ nhiều máy); truy cập property an toàn StrictMode (`PSObject.Properties['...']`)
  — không còn `PropertyNotFoundException` khi model thiếu `release_date`/`name`.
- `modules/ModelCompass/ModelCompass.psm1`: `ConvertTo-McCommandLine` nhận `$Args` rỗng
  (không còn lỗi bind khi gọi lệnh không tham số).
- `scripts/Test-Suite.ps1` giờ chạy **136 test** (103 → 136), pass toàn bộ.
- `README.md`, `ROADMAP.md`: Phase 3 ✅ 4/4 hoàn thành 18/09/2026.

### Ghi chú
- Kết thúc **Phase 3** — toàn bộ ROADMAP Phase 0–3 đã hoàn thành. Docs site deploy sẵn
  trên GitHub Pages sau khi bật `Settings → Pages → Source = GitHub Actions`.
- `mc doctor` cần đúng key: `XTROUTER_API_KEY`, `OMNIROUTE_KEY`, `TEAMO_API_KEY`,
  `NINE_ROUTER_API_KEY` và 2 dịch vụ local OmniRoute (20217) / 9Router (20128).

## [0.5.0] — 2026-09-18 — Phase 2 hoàn tất (2.2–2.6)

### Thêm
- **2.2 Per-project config**: `configs/project-templates/{code,thesis,pentest}/opencode.json`
  (JSON thuần, chỉ `$schema`+`model`+`instructions`) + `docs/per-project-config.md`
  (tầng config, `OPENCODE_CONFIG` / `OPENCODE_CONFIG_CONTENT`, restart, cứu hộ).
- **2.3 Helper sort-order**: `New-SortOrderKey.ps1` (default generate, `-Between/-Append/-Rebuild`,
  chỉ in key không sửa file) + hàm `New-SortOrderKey`/`Get-SortOrderKeyBetween` (tránh trùng key);
  `tests/SortOrder.Tests.ps1` (14 test). Docs `providers-and-models.md §6b` + `configs/README.md`.
- **2.4 Báo cáo drift định kỳ**: `New-ConfigDriftReport.ps1` (validate dev/prod/presets +
  `Get-ConfigDiff` + thống kê model/backup, report offline, `-FailOnInvalid/-FailOnDrift`);
  refactor `Get-ConfigDiff` + `Test-ConfigFile` thành hàm thuần trong `Common-Functions.ps1`
  (`Compare-Config.ps1`, `Test-ModelCompassConfig.ps1` giờ là CLI mỏng);
  `tests/ConfigDiff.Tests.ps1` (11 test); workflow `.github/workflows/report-drift.yml`
  (cron thứ 3 03:00 UTC + `workflow_dispatch`, tự mở/đóng issue label `ci:config-drift`).
- **2.5 Benchmark latency/token**: `Test-ModelConnectivity.ps1 -Benchmark`
  (`-BenchmarkRuns` mặc định 6, `-BenchmarkPrompt/-BenchmarkMaxTokens`) — bắt buộc thu hẹp
  `-Provider/-Model`; hàm `Invoke-Benchmark` (ms + usage token) + `Get-BenchmarkSummary`
  (median/min/max ms, token in/out, tokens/s); report md thêm bảng benchmark;
  `tests/Benchmark.Tests.ps1` (5 test).
- **2.6 Public hoá**: `LICENSE` (MIT), README mở rộng cho người dùng ngoài
  (badge CI + license, cài từ GitHub, tính năng 7–11, cấu trúc mới, đo benchmark).

### Changed
- `scripts/Common-Functions.ps1`: `Test-ConfigFile` truy cập property an toàn StrictMode
  (bỏ `@(...)` với 1 phần tử → dùng `List` accumulation), hết `PropertyNotFoundException`.
- `scripts/Test-Suite.ps1` giờ chạy **103 test** (73 → 103), pass toàn bộ.
- `ROADMAP.md`: Phase 2 ✅ 6/6 hoàn thành 18/09/2026; next = Phase 3.

### Ghi chú
- Kết thúc **Phase 2**. Bắt đầu **Phase 3** (CLI `mc`, provider plugin, model bank, Pages docs)
  khi có nhu cầu thật.

## [0.4.0] — 2026-09-17 — Phase 2.1: preset "safe-mode"

### Thêm
- `configs/presets/safe-minimal.jsonc` — preset cứu hộ: 3 provider free đã test lâu
  (xKiro free remote + OmniRoute/OpenRouter qua local router), **8 model toàn bộ nằm
  trong catalog live 17/09/2026** (cố tình né 5 model `deepseek*` đang vắng trong
  `GET /v1/models`) — 0 chi phí, kèm hướng dẫn rollback nhanh trong comment.

### Changed
- `configs/README.md`: bảng presets + mục "Cứu hộ nhanh".

### Ghi chú
- Bắt đầu **Phase 2** (cứng hoá & mở rộng) — Phase 1 đã hoàn tất 5/5 ở 0.3.x.

## [0.3.4] — 2026-09-17 — Phase 1.5: auto-update STATUS.md (bán tự động)

### Thêm
- `scripts/Test-ModelConnectivity.ps1`: cờ `-UpdateStatus` sinh khối **"Trạng thái gần nhất"**
  từ kết quả probe (marker `<!-- START/END auto-status -->`) rồi chèn/ghi đè vào `STATUS.md`;
  `-StatusPath` cho test/demo; `-SkipRun` để dot-source test.
- `tests/StatusUpdate.Tests.ps1` (5 test) — `ConvertTo-StatusBlock` + `Update-StatusFile`
  (insert khi chưa có marker, replace đúng 1 khối, file thiếu → throw).

### Changed
- `Test-ModelConnectivity.ps1` cấu trúc lại: các hàm thuần đặt phía trên điểm chạy chính.
- `scripts/Test-Suite.ps1` giờ chạy 73 test (68 → 73), pass toàn bộ.

### Ghi chú
- Demo 17/09/2026 trên config tạm: 3 dòng SKIP (thiếu key) → STATUS.md insert đúng 1 khối
  sau tiêu đề, giữ nguyên nội dung gốc; chạy lần 2 → replace (không nhân đôi khối).
- Kết thúc **Phase 1** — Phase 2 tiếp theo là preset "safe-mode".

## [0.3.3] — 2026-09-17 — Phase 1.4: statusline đa provider (quota bar)

### Thêm
- `.opencode/plugins-xkiro/quota-common.js` — module chung: `activeProviders()`
  (đọc `QUOTA_PROVIDERS`, mặc định `xkiro`), `providerDir(name)`,
  `createQuotaStore(name)`, `xkiroKey()`, `summarizeXKiro(data)`.
- `.opencode/plugins-xkiro/xkiro-statusline.tsx` — refactor thành **multi-provider quota bar**:
  render "quota · xKiro free … · provider chưa có …"; tổng tone worst-case;
  env compat `XKIRO_STATUSBAR_*` giữ nguyên.

### Changed
- CI (`validate.yml`) tự động kiểm `quota-common.js` khi loop `node --check`.

### Ghi chú
- `xkiro-usage.js` (server plugin) giữ nguyên — mới chỉ xKiro có endpoint quota thật;
  provider khác fallback "chưa có quota API" (màu trắng, không phải lỗi).
- Không thay đổi bản đồ cache cũ của xKiro (`~/.cache/xkiro`) nên không cần migrate.

## [0.3.2] — 2026-09-17 — Phase 1.3: báo cáo chi phí tổng hợp (đa provider)

### Thêm
- `scripts/Add-SpendEntry.ps1` — ghi 1 phiên (provider, model, token in/out, $)
  vào `reports/spend.jsonl` (append-only, 1 JSON/dòng); tính cost từ token × giá/1M.
- `scripts/Get-SpendReport.ps1` — tổng hợp spend log theo **ngày / provider / top model**:
  filter `-Month/-Day/-Provider/-Model`, xuất bảng console, `-Json` (pipe/script khác),
  `-Report` (Markdown `reports/spend-report-*.md`).
- `scripts/Common-Functions.ps1`: `ConvertTo-SpendCost`, `Get-SpendLogPath`,
  `Add-SpendEntry`, `Get-SpendEntries` (tự chuẩn hoá `ts` thành chuỗi ISO, lướt dòng hỏng).
- `tests/SpendReport.Tests.ps1` (18 test) — ghi/đọc round-trip trên file tạm + hàm thuần.

### Changed
- `scripts/Test-Suite.ps1` giờ chạy 68 test (34 → 50 → 68), pass toàn bộ.

### Ghi chú
- Demo live 17/09/2026: 3 phiên (xkiro gpt-5.6-sol + deepseek free, openrouter deepseek-r2)
  → tổng `$1.36`, tách đúng theo ngày/provider/model; KPI "mỗi phiên trả phí để lại 1 dòng log"
  của ROADMAP §6 đã đạt.

## [0.3.1] — 2026-09-17 — Phase 1.2: so giá config vs catalog live

### Thêm
- `scripts/Compare-Prices.ps1` — trích giá nhồi trong `name` model (`In:$X | Out:$Y`),
  đối chiếu với catalog live (`docs/catalogs/`): báo model giá **đã đổi** ($ + %),
  gợi ý tên mới để copy vào config; tôn trọng strip tiền tố id gateway.
- `tests/Compare-Prices.Tests.ps1` (16 test) — dot-source `-SkipRun`, không gọi mạng.

### Changed
- Tái dùng registry provider của Get-ProviderCatalog (dot-source `-SkipRun`).
- `docs/workflow.md`, `configs/README.md`: thêm bước Compare-Prices trước publish.

### Ghi chú
- Chạy 17/09/2026 so với prod: `2-xkiro-max` **25/25 giá khớp** catalog live;
  provider không nhồi giá free/model không có giá thì báo "không so được" (không phải lỗi).

## [0.3.0] — 2026-09-17 — Phase 1.1: catalog live đa provider

### Thêm
- `scripts/Get-ProviderCatalog.ps1` — gọi `GET /v1/models` cho xKiro/Teamo/OpenRouter/
  OmniRoute/9Router; xuất catalog chuẩn hoá (`context_length`, `access_tier`, `pricing`)
  vào `docs/catalogs/<provider>.json` + snapshot có timestamp vào `reports/catalogs/`;
  so với config để liệt kê model **thiếu / cùng họ / mới chưa khai báo** (`-ShowAllNew`).
- Hỗ trợ strip tiền tố id do gateway local thêm (`openrouter/`) — hết báo thiếu nhầm.
- `tests/Get-ProviderCatalog.Tests.ps1` (11 test) — dot-source không gọi mạng (`-SkipRun`).

### Changed
- `scripts/Test-Suite.ps1` tự động quét mọi `tests/*.Tests.ps1` (hiện 34 test, pass).
- `docs/workflow.md` (Bảo trì) + `configs/README.md` cập nhật cách dùng catalog.

### Ghi chú
- Kết quả chạy 17/09/2026: mọi model config đã khai báo đều có trong catalog live,
  trừ 5 model `1-xkiro-free` + `3-omniroute-free` (xem output script — nguy cơ 404/đổi tên).

## [0.2.0] — 2026-09-17 — Phase 0: vững nền móng

### Thêm
- `scripts/Compare-Config.ps1` — so sánh development vs production (provider set,
  options, model set, model mặc định); mặc định chỉ cảnh báo, `-FailOnDiff` để chốt cứng.
- `scripts/Prune-Backups.ps1` — chính sách backup (giữ N bản mới nhất cho backup
  repo + backup global), có `-DryRun`.
- `tests/ModelCompass.Tests.ps1` + `scripts/Test-Suite.ps1` — Pester v5 cho phần
  lõi scripts/ (JSONC parsing, env resolve, hash, state, validate config, quét key).
- State file cài đặt (sentry): `Install-Config.ps1` / `Restore-RunningConfig.ps1`
  ghi `<target>.state.json` (thời điểm, nguồn, backup, hash) — `Restore -List` hiện
  trạng thái đang dùng + kiểm tra file đang chạy có bị sửa ngoài scripts không.
- CI: chạy Pester, so sánh dev/prod (cảnh báo), `node --check` cho server plugin và
  esbuild syntax-check cho TUI plugin (JSX).
- Ghi chú: bắt buộc `node` (setup-node) trong workflow validate.

### Changed
- Giá/model mới xKiro (free + Max 17/09/2026), catalog OmniRoute/OpenRouter/TeamoRouter,
  `docs/providers-and-models.md`, STATUS.md — snapshot Q3/2026.
- Tài liệu workflow nhấn mạnh bước `Compare-Config` trước/sau publish.

## [0.1.0] — 2026-09-16 — Khởi tạo

### Thêm
- Cấu trúc project ModelCompass (docs, configs 2 giai đoạn, scripts, CI).
- `configs/development/opencode.jsonc` — bản soạn thử có comment hướng dẫn.
- `configs/production/opencode.json` — snapshot cấu hình đang chạy ổn định
  (OmniRoute/Teamorouter/OpenRouter/xKiro/9Router).
- Presets: `fastest-free`, `fastest-paid`, `thesis-writing`, `pentest`.
- Scripts: validate / test connectivity / publish / install / restore + backup.
- GitHub Actions: validate configs + quét API key lộ trong repo.
- Tài liệu: phân tích provider/model (giá 07–09/2026), workflow, recommendations.

### Ghi chú
- Snapshot production chưa đổi nội dung (bản thân config chạy tốt trước đó).
- Dữ liệu giá token là ảnh chụp, cần đối chiếu lại trước khi quyết định trả phí.