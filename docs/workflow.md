# Quy trình làm việc — Workflow

ModelCompass quản lý cấu hình opencode theo **3 lớp** để tối ưu 2 mục tiêu:
**ổn định** (không phá opencode đang dùng) và **tốc độ** (đưa model mới vào nhanh).

```
┌───────────────────┐   Publish-Config.ps1    ┌───────────────────┐   Install-Config.ps1    ┌────────────────────────────┐
│  development/     │ ─── validate + test ──▶ │  production/      │ ─── backup + copy ───▶ │  ~/.config/opencode/       │
│  opencode.jsonc   │                         │  opencode.json    │                         │  opencode.json (đang chạy)  │
│  🚧 sửa thoải mái  │ ◀── (backup .backup/) ──│  ✅ chỉ bản tốt    │ ◀── Restore/rollback ──│                            │
└───────────────────┘                         └───────────────────┘                         └────────────────────────────┘
```

## Nguyên tắc bất biến

1. **Không bao giờ chỉnh tay `production/`.** Mọi thay đổi đến từ `publish`.
2. **Chỉ model/provider đã TEST OK được lên `production/`.** Cache connection/
   cú pháp phải xanh trên máy thật trước khi cài.
3. **Việc áp dụng lên opencode đang chạy là chủ động, không tự động.** Không script
   nào tự sửa `~/.config/opencode/` ngoài `Install-Config.ps1` — và nó luôn backup.
4. **Repo không chứa key.** `{env:...}` là chuẩn duy nhất.
5. **Mọi đổi trên `configs/` phải commit** để truy vết lịch sử (GitHub).

## Các giai đoạn chi tiết

### Giai đoạn A — Soạn thử (development)

- Sửa `configs/development/opencode.jsonc` (có sẵn comment hướng dẫn).
- Hoặc copy model pick từ `configs/presets/*.jsonc`.
- **Tác động**: không ảnh hưởng gì tới opencode đang chạy (file riêng biệt).

### Giai đoạn B — Test (bắt buộc trước publish)

```powershell
# B1. Cú pháp + cấu trúc
pwsh scripts\Test-ModelCompassConfig.ps1 -Path configs\development\opencode.jsonc

# B2. Kết nối thực tế từng provider/model (cần dịch vụ local + bearer key)
pwsh scripts\Test-ModelConnectivity.ps1 -ConfigPath configs\development\opencode.jsonc -Report

# B3. Dùng thử đúng model trong opencode (không đụng config chính):
#     chọn manually đổi model trong TUI, hoặc tạm trỏ config:
$env:OPENCODE_CONFIG="D:\...\01-ModelCompass\configs\development\opencode.jsonc"; opencode
```

**Tiêu chí PASS**: B1 exit 0; B2 không có `ERROR/DOWN/NOTFOUND/TIMEOUT`; B3
dùng thử ổn (không lỗi phiên, tốc độ chấp nhận, không tiêu tốn ngoài dự kiến).

### Giai đoạn C — Publish (development → production)

> 💡 Sửa `docs/workflow.md`. Chạy `Compare-Config` **trước publish** để biết những gì
> sẽ đưa lên prod chuẩn xác, và **-FailOnDiff sau publish** để xác nhận đồng bộ.

```powershell
pwsh scripts\Compare-Config.ps1            # xem lệch dev vs prod (cảnh báo)
pwsh scripts\Publish-Config.ps1 -ConnectivityTest
# Tự động:
#   1) validate lại        2) [tuỳ chọn] test kết nối
#   3) backup production cũ vào configs\production\.backup\
#   4) chuẩn hoá JSON thuần (bỏ comment) rồi ghi production
pwsh scripts\Compare-Config.ps1 -FailOnDiff  # sau publish: expected khớp (trừ model mặc định)
git add configs/production/opencode.json
git commit -m "chore(configs): mô tả model/provider thay đổi"
git push origin main          # CI validate chạy → xanh mới thôi
```

## Bảo trì (khi có nhiều backup)

```powershell
pwsh scripts\Get-ProviderCatalog.ps1          # tải catalog live → docs/catalogs/ + snapshot + so với config
pwsh scripts\Get-ProviderCatalog.ps1 -ShowAllNew   # liệt kê model mới chưa khai báo (mặc định ẩn)
pwsh scripts\Prune-Backups.ps1 -DryRun        # xem sẽ xoá backup nào (repo + global)
pwsh scripts\Prune-Backups.ps1                # giữ 10 bản mới nhất mỗi nơi
pwsh scripts\Test-Suite.ps1                   # chạy toàn bộ test Pester
```

> 📌 Khi thêm model mới: chạy `Get-ProviderCatalog.ps1` trước để chắc model nằm
> trong catalog live (tránh khai báo 404/đổi tên) và đối chiếu model "MISS".

### Giai đoạn D — Install (production → máy đang chạy)

```powershell
pwsh scripts\Install-Config.ps1        # backup .bak-<timestamp> rồi copy
# Quit & restart opencode
```

### Giai đoạn E — Rollback (khi gặp sự cố)

```powershell
pwsh scripts\Restore-RunningConfig.ps1 -List
pwsh scripts\Restore-RunningConfig.ps1 -Backup opencode.json.bak-20260916-100000
```

## Chuẩn hoá production

`Publish-Config.ps1` luôn ghi `production/opencode.json` dạng **JSON thuần**
(tháo comment/trailing comma) để:

- opencode đọc `opencode.json` lại chuẩn (không phụ thuộc khả năng JSONC).
- diff trong Git dễ đọc, lịch sử rõ ràng.

## Vai trò GitHub Actions

`.github/workflows/validate.yml`:

- Validate `production/`, `development/` và mọi presets khi push/PR chạm `configs/`.
  → Không cho merge PR đưa config hỏng vào nhánh chính.
- Quét API key lọt trong `configs/` (`sk-…`, `AIza…`, Bearer token) → fail nếu có.

## Checklist trước khi "release" model mới

- [ ] Model xuất hiện và gọi được trên provider (B2 xanh).
- [ ] Tên model/my (hiển thị trong opencode) ghi rõ giá + nhận dạng free/paid.
- [ ] API key không hardcode (dùng `{env:...}`).
- [ ] Doanh thu/chi phí đã ước lượng nếu là model trả phí (xem pricing doc).
- [ ] Đã publish + commit + CI xanh.
- [ ] Đã install + restart + kiểm tra thực tế.