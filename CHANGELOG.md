# Changelog

Tạo theo chuẩn [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) +
[Semantic Versioning](https://semver.org/). Mỗi release = một mốc cấu hình hoặc
bộ nâng cấp quy trình được "đóng gói" và commit lên GitHub.

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