# 🗺️ ROADMAP — ModelCompass

> Bản xem lại tổng thể dự án **ModelCompass** (kho `son8x/ModelCompass`, ngày review
> **17/09/2026**), kèm phương án cải tiến và lộ trình phát triển theo giai đoạn.
> Trạng thái dự án tại thời điểm review: **ổn định**, đang chuyển từ "dự án cá nhân"
> thành "chuẩn quản lý model/provider có thể tái dùng".

---

## 1. Tóm tắt đánh giá

| Khía cạnh | Đánh giá | Ghi chú |
|---|---|---|
| Kiến trúc quy trình | ⭐ Rất tốt | 2 giai đoạn dev → prod + backup/rollback, nguyên tắc bất biến rõ ràng |
| Bảo mật key | ⭐ Rất tốt | `{env:...}` chuẩn duy nhất, `.env.local` bị ignore, CI quét rò rỉ |
| Chất lượng tooling | 👍 Tốt | 7 script PowerShell rõ ràng, có mã thoát, hỗ trợ non-interactive |
| Tài liệu | 👍 Tốt | pricing, recommendations, workflow, STATUS đầy đủ nhưng cần chống "drift" |
| Mở rộng plugin | 🚧 Đang hình thành | xKiro usage (script + server plugin + TUI statusline) mới chỉ phủ 1 provider |
| Kiểm thử tự động | 🚧 Thiếu | CI chỉ validate cú pháp; không test Pester, không test plugin TS/TSX |
| Phiên bản hoá | ⚠️ Yếu | CHANGELOG vẫn 0.1.0 trong khi có 2 lần thay đổi lớn sau đó |

**Kết luận**: nền móng tốt. Ưu tiên chính không phải "thêm tính năng mới" mà là
**đóng kín vòng kiểm thử, tự động hoá các bước thủ công đang lặp lại, và mở rộng
giám sát chi phí ra khỏi phạm vi xKiro**.

---

## 1b. Tiến độ triển khai (giám sát)

> **Ký hiệu**: ✅ hoàn thành · 🔶 đang làm · ⬜ chưa bắt đầu · ⚪ hoãn/loại bỏ.
> Cập nhật bảng này mỗi khi hoàn tất một hạng mục.

| Giai đoạn | Trạng thái | Tiến độ | Ghi chú |
|---|---|---|---|
| **Phase 0 — Vững nền móng** | ✅ | 6/6 (7/7 nhiệm vụ) | hoàn thành 17/09/2026 |
| **Phase 1 — Sống hoá dữ liệu & giám sát chi phí** | ✅ | 5/5 | hoàn thành 17/09/2026 |
| **Phase 2 — Cứng hoá & mở rộng** | 🔶 | 1/6 | đang làm — 2.1 xong 17/09/2026 |
| **Phase 3 — Hệ sinh thái mở** | ⬜ | 0/4 | khi có nhu cầu |

**Next action đang chờ**: Phase 2 hạng mục 2.2 — per-project config (template + OPENCODE_CONFIG hook tầng).

---

## 2. Điểm mạnh cần giữ

1. **Quy trình 2 giai đoạn + backup**: không bao giờ chạm config đang chạy ngoài
   `Install-Config.ps1`, luôn backup trước khi ghi đè → rollback tức thì.
2. **An toàn key chuẩn chỉnh**: `setup-opencode-env.ps1` che key, tự chặn nếu
   `.env.local` lọt vào git, tạo `.env.sample` an toàn để commit.
3. **CI thực thụ**: validate cú pháp + quét API key trên mỗi push/PR chạm `configs/`.
4. **Chống sort-order trong `/model`** bằng `release_date` tổng hợp đã được nghiên cứu
   và ghi recipe kỹ (`docs/providers-and-models.md` §6, `configs/README.md`).
5. **Tài liệu theo use-case** (programming / thesis / pentest) kèm giá + cách cấu hình.

---

## 3. Điểm yếu / Điểm nghẽn hiện tại

| # | Vấn đề | Mức độ | Hậu quả nếu để lâu |
|---|---|---|---|
| 1 | **`production/` và `development/` có thể lệch nhau** — không có chốt chặn nào kiểm tra 2 file đồng bộ | Cao | Publish nhầm/thiếu, mất model đã test |
| 2 | **STATUS.md + bảng giá là "thủ công"** — phụ thuộc nhớ cập nhật mỗi lần test | Cao | Tài liệu hết giá trị khi giá/model provider đổi |
| 3 | **Giám sát hạn mức chỉ có xKiro** — Teamo/OmniRoute/OpenRouter không có ghi chép chi phí | Trung bình | Không biết chi tiêu thực tế, dễ vượt budget |
| 4 | **Không có test Pester / kiểm tra build plugin TUI (TSX) trong CI** | Trung bình | Plugin hỏng về sau mà không ai hay |
| 5 | **Hook mở rộng ràng buộc theo bản opencode** (`release_date`, sort) — mong manh trước update | Trung bình | Thứ tự `/model` đảo loạn sau upgrade |
| 6 | **Backup `.backup/`, `.bak-*` chất đống** — không có chính sách giữ/xoá | Thấp | Repo phình, khó tìm đúng bản |
| 7 | **Semver + CHANGELOG không bám** — 2 release lớn nhưng version không tăng | Thấp | Mất dấu vết "release" nào đang chạy |
| 8 | **Versions "ảo" của provider (2099) và tên model dài** — khó đọc khi debug log | Thấp | Hiểu lầm, khó parse log |

---

## 4. Định hướng phát triển (3 trục)

1. **Đóng vòng tin cậy (Reliability)**: tự động hoá so sánh dev↔prod, test có thể chạy
   lại (Pester), CI bảo vệ cả plugin lẫn config, chính sách backup.
2. **Biến dữ liệu thành "sống" (Data-driven)**: kéo live catalog/giá từ provider
   (`GET /v1/models` đã dùng thủ công cho xKiro) → scan tự động, báo diff, cập nhật
   docs/STATUS bán tự động, thống kê chi phí đa provider.
3. **Mở rộng hệ sinh thái (Ecosystem)**: giám sát quota theo plugin dùng chung,
   preset "an toàn tối thiểu" để cứu hộ, per-project config cho từng use-case,
   tài liệu/README chuẩn để người khác dùng lại.

---

## 5. Lộ trình chi tiết

> Ước lượng khối lượng theo nỗ lực người dùng cá nhân (S/M/L). **P0 = làm ngay**,
> **P1 = tiếp theo**, **P2 = khi có nhu cầu thật**.

### Phase 0 — Vững nền móng (tuần 1) — ✅ hoàn thành 17/09/2026

| # | Hạng mục | Mô tả | Ưu tiên | Kích thước | File liên quan | Trạng thái |
|---|---|---|---|---|---|---|
| 0.1 | **Chốt đồng bộ dev ↔ prod** | Thêm script `Compare-Config.ps1 -Dev -Prod` (so model set, options, default model) + chạy trong CI như **warning** (không fail vì 2 file có thể lệch chủ đích) | P0 | S | `scripts/`, `.github/workflows/validate.yml` | ✅ |
| 0.2 | **Sentry cho rollback** | `Restore-RunningConfig.ps1` thêm chế độ `-StateFile` ghi metadata (ngày, ghi chú, hash) để biết "bản nào đang được install" | P0 | S | `scripts/Restore-RunningConfig.ps1`, `Install-Config.ps1` | ✅ |
| 0.3 | **Policy backup** | Script `Prune-Backups.ps1` (giữ N bản mới nhất mỗi loại, mặc định 10), cài vào workflow của repo | P0 | S | `scripts/`, README | ✅ |
| 0.4 | **Test Pester cho `Common-Functions` + validate** | `tests/ModelCompass.Tests.ps1` (parse JSONC, resolve env, detect key) — chạy được local lẫn CI | P0 | M | `tests/`, `scripts/Common-Functions.ps1` | ✅ |
| 0.5 | **Kiểm build plugin TUI trong CI** | `node --check` cho server plugin `.js` + esbuild syntax-check (JSX) cho `xkiro-statusline.tsx` | P0 | S | `.github/workflows/validate.yml` | ✅ |
| 0.6 | **Bump version + CHANGELOG chuẩn semver** | Version hoá theo release production (vd 0.2.0 cho bộ thay đổi 16–17/09 đã có) | P1 | S | `CHANGELOG.md` | ✅ |

### Phase 1 — Sống hoá dữ liệu & giám sát chi phí (tuần 2–3)

| # | Hạng mục | Mô tả | Ưu tiên | Kích thước | Trạng thái |
|---|---|---|---|---|---|
| 1.1 | **`Get-ProviderCatalog.ps1`** | Gọi `GET /v1/models` của xKiro/Teamo/OpenRouter/OmniRoute/9Router (OpenRouter có sẵn pricing) → xuất `docs/catalogs/<provider>.json` + snapshot `reports/catalogs/`, so với config để liệt kê model thiếu/404/mới — có test Pester | P1 | L | ✅ |
| 1.2 | **`Compare-Prices.ps1`** | So sánh giá (input/output) trong config vs live catalog → báo mức chênh, gợi ý cập nhật tên model (giá đang nhồi vào `name`) — có test Pester | P1 | M | ✅ |
| 1.3 | **Báo cáo chi phí tổng hợp** | `Add-SpendEntry.ps1` ghi mỗi phiên (model, token in/out, $) vào `reports/spend.jsonl` (đa provider, mở rộng từ xKiro); `Get-SpendReport.ps1` tổng hợp theo ngày/provider/model, xuất bảng/`-Json`/`-Report` md — có test Pester | P1 | L | ✅ |
| 1.4 | **Statusline đa quota** | `quota-common.js` tách logic chung; `xkiro-statusline.tsx` đọc `QUOTA_PROVIDERS` env (mặc định xkiro), render multi-segment "quota · xKiro free … · teamo chưa có …"; giữ env tương thích `XKIRO_STATUSBAR_*`; CI esbuild syntax-check pass | P1 | M | ✅ |
| 1.5 | **Auto-update STATUS.md** | `Test-ModelConnectivity.ps1 -UpdateStatus` sinh khối "Trạng thái gần nhất" (marker auto-status) rồi chèn/ghi đè vào `STATUS.md` bán tự động; `-StatusPath` cho test/demo — có test Pester | P1 | M | ✅ |

### Phase 2 — Cứng hoá & mở rộng (tháng 1)

| # | Hạng mục | Mô tả | Ưu tiên | Kích thước |
|---|---|---|---|---|
| 2.1 | **Preset "safe-mode"** | `configs/presets/safe-minimal.jsonc`: 3 provider free đã test lâu (8 model toàn nằm trong catalog live), chỉ dùng khi nghi ngờ config mới gây lỗi + hướng dẫn rollback nhanh | P1 | S | ✅ |
| 2.2 | **Per-project config** | Tài liệu + template `opencode.json` cho từng project (thesis/pentest/code) dùng `OPENCODE_CONFIG` hook tầng, không đụng global | P2 | M |
| 2.3 | **Phân cụm sort-order** | Tách "khoá sắp xếp" ra 1 quy ước dùng chung (helper tạo key 2099 từ nhóm/giá) để thêm model không phải chỉnh tay date rải rác | P2 | M |
| 2.4 | **Scheduled -report trên CI** | Cron GitHub Actions chạy `Test-ModelCompassConfig` + (không cần mạng local) báo cáo lệch dev/prod + size backup — issue tự động | P2 | S |
| 2.5 | **Đo latency/token thực** | `Test-ModelConnectivity.ps1` thêm tham số `-Benchmark` (N lần, ghi ms + tokens) → dữ liệu tốc độ thực tế cho `docs/providers-and-models.md` | P2 | M |
| 2.6 | **License & chuẩn hoá public** | Thêm LICENSE (MIT), mở rộng README cho người dùng ngoài (env vars, cách fork, disclaimer giá) | P2 | S |

### Phase 3 — Hệ sinh thái mở (tháng 2+, khi cần)

| # | Hạng mục | Mô tả | Ưu tiên | Kích thước |
|---|---|---|---|---|
| 3.1 | **"ModelCompass CLI"** | Gói gọn các script thành `mc` (PowerShell module) với command: `mc sync`, `mc publish`, `mc status`, `mc report`, `mc doctor` (kiểm local services OmniRoute/9Router) | P2 | L |
| 3.2 | **Provider plugin để người dùng tự đóng góp** | Chuẩn hoá cách khai báo provider mới (template + recipe), CI chấp nhận preset mới | P2 | M |
| 3.3 | **Export sang dạng dùng chung** | Sinh `configs/production/opencode.json` + `presets` thành "model bank" JSON có schema, để các công cụ khác (đồng bộ nhiều máy) tiêu thụ | P2 | L |
| 3.4 | **GitHub Pages docs** | Dựng trang kubey đọc `docs/` làm "nơi tra cứu model theo giá/tác vụ" | P2 | M |

---

## 6. KPI đề xuất (đo mức độ hoàn thiện)

- **Test coverage**: ≥ 60% cho `Common-Functions` + các script validate qua Pester.
- **CI xanh 100%**: mọi push/PR chạm `configs/` hoặc `.opencode/` đều validate.
- **Độ lệch 0**: `Compare-Config` không báo lệch bất ngờ (trừ thay đổi chủ đích có commit).
- **Dữ liệu "sống"**: catalog chạy ≤ 48h trước mỗi lần publish; chênh lệch giá >10% được cảnh báo.
- **Chi phí nhìn thấy được**: mỗi phiên trả phí để lại 1 dòng log spend có provider + model + $.

---

## 7. Rủi ro & giảm thiểu

| Rủi ro | Khả năng | Giảm thiểu |
|---|---|---|
| opencode đổi cơ chế sort (`release_date`) | Trung bình | Tập trung quy ước vào 1 file/helper (2.3); theo dõi changelog opencode; test nhanh khi upgrade |
| Giá/model provider đổi nhanh hơn tài liệu | Cao | Đưa live catalog vào quy trình publish (1.1, 1.2); STATUS đổi sang "bán tự động" |
| Plugin TUI vỡ màn hình khi opencode update API | Trung bình | CI build/type-check plugin (0.5); fallback khi API thiếu (1.4) |
| Key lộ do copy lộn sang preset/docs | Thấp | Giữ regex quét trong CI, mở rộng sang **toàn repo** (không chỉ `configs/`) |
| Backup chất đống làm repo phình | Thấp | Prune-Backups + chuyển `.backup/` sang lưu 10 bản gần nhất |

---

## 8. Gợi ý bước đi ngay (sau Phase 0)

1. **Phase 2 (2.2)**: tạo template + docs per-project config (P2 — đã xong 2.1).
2. **Prune-Backups**: cài vào lịch (hoặc chạy thủ công hằng tuần) để giữ repo gọn.
3. **Thực thi workflow mới**: trước publish chạy `Compare-Config`, sau publish chạy `Compare-Config -FailOnDiff` để xác nhận đồng bộ.
4. **Kiểm `Restore-RunningConfig.ps1 -List`** trên máy thật để xác nhận state file (sentry) hiển thị đúng.

---

*Sinh bởi review tổng thể ModelCompass — ngày 17/09/2026. Cập nhật file này mỗi khi đánh giá lại định hướng.*