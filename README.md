# 🧭 ModelCompass

Dự án **phân tích, đánh giá và quản lý cấu hình AI provider/model** cho
[opencode](https://opencode.ai) — trải rộng từ **miễn phí** đến **trả phí**,
kèm theo quy trình **an toàn** để đưa model mới vào sử dụng mà **không làm hỏng
opencode đang chạy**.

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

---

## 📁 Cấu trúc

```
01-ModelCompass/
├── README.md                  ← bạn đang ở đây
├── docs/
│   ├── providers-and-models.md   ← phân tích chi tiết provider/model
│   ├── workflow.md               ← quy trình development → production → release
│   └── recommendations/          ← đề xuất theo nhu cầu (lập trình / luận văn / pentest)
├── configs/
│   ├── development/opencode.jsonc  ← 🚧 soạn thử (sửa thoải mái)
│   ├── production/opencode.json    ← ✅ đã test, dùng để cài đặt
│   └── presets/*.jsonc             ← model pick theo use case
├── scripts/                    ← PowerShell 7: validate / test / publish / install / restore
├── reports/                    ← kết quả test (gitignored)
└── .github/workflows/validate.yml ← CI
```

## 🚀 Quickstart (lần đầu)

```powershell
# 1) Kiểm tra cấu hình production hợp lệ
pwsh scripts\Test-ModelCompassConfig.ps1

# 2) (Tùy chọn) Ping thử connectivity của từng provider/model trong development
pwsh scripts\Test-ModelConnectivity.ps1 -ConfigPath configs\development\opencode.jsonc

# 3) Cài config production đang có lên opencode global (có backup tự động)
pwsh scripts\Install-Config.ps1
#    → Quit & restart opencode
```

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

## 📊 Nguồn dữ liệu giá

Bảng giá token là **ảnh chụp tại thời điểm viết** (Q4/2026), có ghi nguồn trong
`docs/providers-and-models.md`. Giá nhà cung cấp thay đổi thường xuyên — trước
khi quyết định trả phí, hãy xác nhận lại trên trang chính thức của provider.

---

*Powered by ModelCompass — tìm đúng model, chạy đúng cấu hình.*