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
| `TEAMO_API_KEY` | Provider `teamoRouter` |
| `OMNIROUTE_KEY` | Provider `omniroute-free`, `openrouter-free` |
| `XTROUTER_API_KEY` | Provider `xkiro-free`, `xkiro-max` |
| `NINE_ROUTER_API_KEY` | Provider `9router` |

> Cấu hình dùng cơ chế `{env:TÊN_BIEN}` của opencode — repo không chứa key.

> 🎯 **Thứ tự hiển thị trong `/model` = thứ tự khai báo block `provider` trong
> file cấu hình** (opencode giữ nguyên thứ tự, không đánh số). Muốn đổi thứ tự
> ưu tiên chỉ cần kéo lên/xuống block — không phải sửa số như trước đây
> (`1-teamoRouter`, `2-omniroute-free`, …).

## Các script liên quan (xem `../scripts/`)

- `Test-ModelCompassConfig.ps1` — validate cú pháp/cấu trúc JSON(C).
- `Test-ModelConnectivity.ps1` — ping thực tế từng provider/model.
- `Publish-Config.ps1` — promote `development` → `production` (sau validate).
- `Install-Config.ps1` — cài `production` vào thư mục global opencode.
- `Restore-RunningConfig.ps1` — khôi phục backup nếu có sự cố.

## Presets hiện có

| Preset | Dùng cho |
|--------|----------|
| `presets/fastest-free.jsonc` | Model miễn phí, tốc độ cao (code/sửa lỗi hằng ngày) |
| `presets/fastest-paid.jsonc` | Model trả phí giá rẻ, hiệu năng cao |
| `presets/thesis-writing.jsonc` | Viết luận văn (văn phong hàn lâm, tiếng Việt) |
| `presets/pentest.jsonc` | Pentest / bảo mật (reasoning, phân tích mã) |

Cách dùng preset: copy block `"provider"` (hoặc từng entry) mong muốn vào
`development/opencode.jsonc` → validate → test → publish.