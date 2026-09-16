# Changelog

Tạo theo chuẩn [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) +
[Semantic Versioning](https://semver.org/). Mỗi release = 1 cấu hình production
được "đóng gói" và commit lên GitHub.

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