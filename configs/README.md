# Configs — ModelCompass

Thư mục chứa các cấu hình opencode được **quản lý phiên bản** và áp dụng theo quy trình **2 giai đoạn** (development → production) để không làm hỏng opencode đang chạy.

## Cấu trúc

| Đường dẫn | Vai trò | Trạng thái |
|-----------|---------|-----------|
| `development/opencode.jsonc` | Bản **soạn thử** — sửa thoải mái, có comment | 🚧 WIP |
| `production/opencode.json` | Bản **đã test OK** — dùng để cài đặt | ✅ Ổn định |
| `presets/*.jsonc` | Bộ cấu hình mẫu theo nhu cầu (memory: merge thủ công) | 📦 Tham khảo |

## Nguyên tắc an toàn (không bao giờ ghi đè opencode đang chạy)

```
development/  ──Publish-->  production/  ──Install-->  ~/.config/opencode/opencode.json
     ▲                                    (có backup)
     └── chỉ được publish khi TEST OK
```

1. **`production/opencode.json`** là ảnh chụp cấu hình đang chạy tốt trên máy
   (`~/.config/opencode/opencode.json`) tại thời điểm khởi tạo kho.
2. Mọi thử nghiệm mới ghi vào **`development/opencode.jsonc`**.
3. Chỉ model/provider **đã ping OK và dùng thử ổn** mới được promote lên `production/`.
4. `Install-Config.ps1` luôn **backup** file hiện có trước khi ghi đè.

## Env vars bắt buộc (đặt trong môi trường, KHÔNG ghi vào repo)

| Biến | Dùng cho |
|------|----------|
| `TEAMO_API_KEY` | Provider `6-teamoRouter` |
| `OMNIROUTE_KEY` | Provider `3-omniroute-free`, `4-openrouter-free` |
| `XTROUTER_API_KEY` | Provider `1-xkiro-free`, `2-xkiro-max` |
| `NINE_ROUTER_API_KEY` | Provider `5-9router` |

> Cấu hình dùng cơ chế `{env:TÊN_BIEN}` của opencode — repo không chứa key.

> 🎯 **Thứ tự hiển thị trong `/model` = sắp xếp theo key (provider id) + name
> theo bảng chữ cái**, nên PHẢI đánh số thứ tự `1-`, `2-`, … ở đầu key VÀ name
> mỗi provider để ép đúng thứ tự ưu tiên (xem file config hiện tại). Muốn đổi
> thứ tự: sửa lại số, không cần di chuyển block (so sánh theo chuỗi, tránh số >9
> nếu cần — dùng `1-`…`9-`).
> (Thứ tự cũ 2026 dùng `1-teamoRouter`, `2-omniroute-free`, … nay đổi ưu tiên:
> `1-xkiro-free → 2-xkiro-max → 3-omniroute-free → 4-openrouter-free →
> 5-9router → 6-teamoRouter`.)
>
> 🌟 **Thứ tự MODEL trong mỗi provider**: opencode KHÔNG giữ thứ tự khai báo — nó sort theo
> `release_date` GIẢM DẦN rồi mới tới `name` A→Z. Muốn ép thứ tự model (vd theo giá/độ mạnh),
> gán `"release_date"` (string, chỉ dùng làm khoá sắp xếp — không hiển thị trên UI):
> model hiện trên cùng có `release_date` LỚN nhất; đặt trùng nhau sẽ fallback về `name` A→Z.
> 2 provider xKiro đang dùng quy ước `2099-<MM>-<DD>` giảm dần 1 ngày/lượt.
> Chi tiết + recipe: `docs/providers-and-models.md` §6.

## Các script liên quan (xem `../scripts/`)

- `Test-ModelCompassConfig.ps1` — validate cú pháp/cấu trúc JSON(C).
- `Test-ModelConnectivity.ps1` — ping thực tế từng provider/model.
- `Publish-Config.ps1` — promote `development` → `production` (sau validate).
- `Install-Config.ps1` — cài `production` vào thư mục global opencode (ghi state file).
- `Restore-RunningConfig.ps1` — khôi phục backup nếu có sự cố (xem state + hash).
- `Compare-Config.ps1` — so sánh dev vs prod (chống lệch trước/sau publish).
- `Get-ProviderCatalog.ps1` — tải catalog live của xKiro/Teamo/OpenRouter/OmniRoute/9Router → `docs/catalogs/`, so với config để liệt kê model **thiếu/đổi tên/mới** (hỗ trợ strip tiền tố id gateway, `-ShowAllNew`).
- `Prune-Backups.ps1` — chính sách giữ/xoá backup (repo + global).
- `Test-Suite.ps1` — chạy toàn bộ test Pester (`tests/`).

## Presets hiện có

| Preset | Dùng cho |
|--------|----------|
| `presets/fastest-free.jsonc` | Model miễn phí, tốc độ cao (code/sửa lỗi hằng ngày) |
| `presets/fastest-paid.jsonc` | Model trả phí giá rẻ, hiệu năng cao |
| `presets/thesis-writing.jsonc` | Viết luận văn (văn phong hàn lâm, tiếng Việt) |
| `presets/pentest.jsonc` | Pentest / bảo mật (reasoning, phân tích mã) |

Cách dùng preset: copy block `"provider"` (hoặc từng entry) mong muốn vào
`development/opencode.jsonc` → validate → test → publish.