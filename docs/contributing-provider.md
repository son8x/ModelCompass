# Đóng góp provider mới — chuẩn hoá + recipe

Hướng dẫn thêm **một provider opencode** vào ModelCompass theo cách chuẩn để CI
chấp nhận và mọi thành viên dùng lại được. Bắt đầu từ mẫu:

- `configs/provider-template/opencode.json` — bộ khung đầy đủ 1 provider + 1 model.
- `configs/project-templates/{code,thesis,pentest}/opencode.json` — template per-project
  (dùng `OPENCODE_CONFIG`; xem `docs/per-project-config.md`).

## Quy ước đặt tên

| Thành phần | Quy ước | Ví dụ |
|---|---|---|
| Provider id | `N-ten-hay-nho`, `N` = số thứ tự nhóm, không dấu | `6-teamoRouter` |
| Model id | nguyên bản từ API (không thêm tiền tố gateway) | `minimax/minimax-m3:free` |
| Biến môi trường | `UPPER_SNAKE`, đặt tên rõ nhà cung cấp | `MY_PROVIDER_API_KEY` |
| `name` model | `Tên Đẹp | In:$X | Out:$Y` (giá /1M token để `Compare-Prices` parse) | `My Model | In:$0.10 | Out:$0.20` |
| `release_date` | dạng `yyyy-MM-dd` qua helper `New-SortOrderKey.ps1` | `2099-12-31` |

## Recipe (đi từng bước)

1. **Khai báo trong development**: copy `provider-template/opencode.json` vào
   `configs/development/opencode.jsonc`, đổi tên provider/model/env theo quy ước.
2. **Validate cú pháp + cấu trúc**:
   ```powershell
   mc validate -Path configs/development/opencode.jsonc
   # hoặc: pwsh scripts\Test-ModelCompassConfig.ps1 -Path ...
   ```
   Nhớ đặt biến môi trường (xem `mc env`) để bước validate hết cảnh báo `{env:...}`.
3. **Đối chiếu catalog live** (nếu provider có `GET /v1/models`):
   ```powershell
   mc sync            # Get-ProviderCatalog.ps1 — nạp catalog vào docs/catalogs/
   mc prices          # Compare-Prices.ps1 — so giá config vs catalog
   ```
4. **Test kết nối thật**:
   ```powershell
   mc connectivity -Provider '6-teamoRouter'      # ping từng model
   mc benchmark -Provider '6-teamoRouter' -Model '<id>'   # latency + tokens/s
   ```
5. **Dùng thử** với `OPENCODE_CONFIG` rồi restart opencode (không đụng global).
6. **Publish**: `mc publish -ConnectivityTest` (dev → prod, có backup).
7. **Commit** + đẩy lên GitHub — CI (`validate.yml`) tự validate:
   - `configs/production/opencode.json` & `configs/development/opencode.jsonc`;
   - **mọi preset mới** trong `configs/presets/*.jsonc` (tự động, không cần sửa workflow);
   - mọi template `configs/project-templates/*/opencode.json` + `configs/provider-template/*.json`;
   - toàn bộ test Pester (`tests/`, kể cả `Templates.Tests.ps1`);
   - quét rò rỉ API key trong `configs/`.

## Điều kiện CI chấp nhận (checklist)

- [ ] File config parse được (JSON/JSONC hợp lệ).
- [ ] Có `"$schema"` và `"model"` đúng dạng `provider/model-id`.
- [ ] Mọi provider có ≥ 1 model; `options.baseURL` + `npm` khai báo.
- [ ] API key chỉ qua `{env:TÊN_BIẾN}` — **không được có giá trị key trong repo**.
- [ ] Đã ping OK (`mc connectivity`) — với free model thường là `OK`.
- [ ] `release_date` dùng helper sort-order (tránh date trùng nhau).

## Các bước nếu CI chặn

| Lỗi CI | Cách xử lý |
|---|---|
| `Tests Passed: n, Failed: 1` (Templates.Tests) | Đọc tên test fail — thường là parse JSON / thiếu `$schema`/`model` |
| "Phát hiện chuỗi giống API key" | Xoá giá trị key thật; chỉ giữ `{env:...}` |
| "không có biến môi trường" | Không phải lỗi nếu env của BẠN chưa set trên CI — preset không dùng `-Strict` |

> Mẹo: preset/provider mới không cần sửa workflow — validate.yml tự quét toàn bộ
> `configs/presets/` và `configs/project-templates/`. Nếu bạn thêm **loại file mới**
> (vd `configs/xxx/`), hãy nhắc maintainer cập nhật `validate.yml` + `Templates.Tests.ps1`.