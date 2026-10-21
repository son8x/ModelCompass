# AGENTS.md — Hướng dẫn làm việc trong repo ModelCompass

Tài liệu này dành cho **mọi session (agent/con người) làm việc trong dự án này**.
Đọc trước khi sửa config hoặc script. Các mục "⚠️" là lỗi **đã xảy ra thật** —
lặp lại sẽ làm hỏng opencode cho toàn bộ máy.

---

## ⚠️ BÀI HỌC 2026-10-19 — `"npm"` của provider, và lỗi `Failed to initialize provider`

### Sự cố

```text
level=ERROR ... error="Failed to initialize provider: 1-xkiro-free|2-xkiro-max"
```

- 7 lần trong `C:/Users/son/.local/share/opencode/log/opencode.log`,
  2026-10-19 09:00 → 09:24 (giờ máy). **Tất cả model xKiro biến mất**, không chọn được.
- log KHÔNG có `Cannot find package` / `ENOENT` / `ERR_MODULE` → rất dễ chẩn đoán nhầm.

### Nguyên nhân gốc

`configs/{development,production}` bị đổi:

```diff
-  "npm": "@ai-sdk/openai-compatible",    ✅ dùng được
+  "npm": "@modelscope/providers",        ❌ KHÔNG tồn tại
```

```powershell
npm view @modelscope/providers version     # → npm error 404 Not Found
npm view @ai-sdk/openai-compatible version # → 3.0.71
```

Package `@modelscope/providers` **đã bị gỡ khỏi registry npm (404)**. opencode không
resolve được custom provider → `Failed to initialize provider`. API key và `baseURL`
hoàn toàn bình thường (49/49 model ping `OK`), nên **không phải lỗi key**.

- Introduce bởi commit `f388b2a` (sửa `provider.name` — sửa nhầm luôn dòng `npm`).
- Không có package này ở bất kỳ đâu trên ổ đĩa: `node_modules`, npm cache,
  bun cache → chứng minh nó chưa bao giờ cài được thật.

### ✅ Quy tắc bắt buộc

1. **KHÔNG BAO GIỜ sửa/chỉ định dòng `"npm"`** trừ khi bạn đang thêm provider mới
   và đã tự kiểm chứng. Provider dùng OpenAI-compatible API (gồm cả xKiro) luôn là:
   ```jsonc
   "npm": "@ai-sdk/openai-compatible"
   ```
2. **Luôn chạy `npm view <tên-package> version` TRƯỚC** khi ghi một package `npm`
   vào config. `E404` = dừng ngay.
3. **Sau MỌI edit vào config**: soi `git diff` từng dòng — edit tool có thể khớp
   nhầm/khớp lỏng block JSON, thay cả dòng bạn không định sửa.
4. **Chuỗi kiểm chứng tối thiểu** (chạy hết, exit 0 mới commit):
   ```powershell
   pwsh scripts/test/Test-Suite.ps1                # Pester, phải Passed: 303+
   pwsh scripts/config/Test-ModelCompassConfig.ps1 # validate
   pwsh scripts/config/Compare-Config.ps1          # dev vs prod = 0 diff
   pwsh scripts/config/Install-Config.ps1 -Force   # có backup
   & "C:\Programs\OpenCode\opencode.exe" models    # có model xKiro, không error
   ```

### ✅ Cách chẩn đoán nhanh lần sau

```powershell
# 1. Lấy lỗi thật từ log (không đoán)
Select-String -Path 'C:\Users\son\.local\share\opencode\log\opencode.log' `
  -Pattern 'Failed to initialize provider'

# 2. Kiểm tra package có tồn tại không
npm view @ai-sdk/openai-compatible version

# 3. Reproduce không tương tác (in log init ra console)
& "C:\Programs\OpenCode\opencode.exe" run --print-logs --log-level ERROR `
  -m "1-xkiro-free/cohere/aya-expanse-32b" "Reply with exactly: OK"
```

---

## Quy tắc sửa `provider.name` (bug cộng dồn)

Dạng chuẩn: `<base> — <count> model` (**em dash U+2014**, không phải `-` U+002D).

```text
1. xKiro Free — 49 model
2. xKiro Max — 47 model
```

- **Không bao giờ** đặt tay hậu tố số model vào config — để
  `Format-ProviderHeader` (`scripts/provider/Update-XKiroModels.ps1`) sinh ra.
- Hàm này strip hậu tố cũ rồi tái tạo; regex **phải khớp cả `—` lẫn `-`**:
  ```powershell
  $base = $Name -replace '\s*(?:—|-)\s*\d+\s*model.*$', ''
  ```
  Bug cũ chỉ khớp `—` → name thành `1. xKiro Free - 51 model — 49 model` (cộng dồn).
  Regression test: `tests/Update-XKiroModels.Tests.ps1` → `Describe 'Format-ProviderHeader'`.
- Khi sửa script, đừng quên giữ **indent** khối provider như nguyên bản
  (key 4 space, `npm`/`name`/`options` 6 space trong production).

## Không viết tay phụ chú vào `name`

`(gỡ: a, b, c)` / `(+N)` bị cấm trong config (làm picker/khung chat quá dài).
Chi tiết thêm/gỡ ghi ở `STATUS.md` / `CHANGELOG.md`.
Xem thêm `docs/market-intel.md` (chiến lược), `docs/model-reference.md` (canonical ⭐).

## xKiro có nhiều modality — `/v1/models` mặc định CHỈ trả chat

`GET /v1/models` **loại image/audio/search khỏi picker**. Xin thêm bằng
`?modality=image|tts|search|all`. `mc sync` tự lưu riêng:
`docs/catalogs/xkiro-image.json` + `xkiro-tts.json` (đừng trộn vào `xkiro.json`).

- **CHỈ model `modality=chat` mới thêm được vào khối `provider.models`** trong config.
  Image/TTS gọi qua **endpoint riêng** (`/v1/images/generations`, `/v1/audio/speech`),
  opencode không hiển thị → đừng đưa vào config.
- **xKiro KHÔNG có text→video.** Chỉ hiểu video đầu vào (Qwen VL) + TTS. MiniMax ở
  xKiro là model chat M-series, KHÔNG phải Hailuo/video.
- Image là job bất đồng bộ (POST `202` → poll job id); TTS tính phí theo ký tự.
- Chi tiết 4 nhóm: `docs/model-reference.md` §1b.

> ⚠️ Bẫy PowerShell: trong **hashtable**, `$h.PSObject.Properties['X']` LUÔN false —
> phải dùng trực tiếp `$h.X` (bug guard `ServiceModalities` 21/10).

---

## Môi trường (Windows / PowerShell)

| Sự thật | Việc phải làm |
|---|---|
| `bash` tool chạy **PowerShell 5.1** | Không có `&&`, `\| tail`, `\| head`. Dùng `cmd1; if ($?) { cmd2 }` |
| Inline `pwsh -Command "..."` bị shell nuốt `$var` | **`write` script `.ps1` tạm rồi `pwsh -NoProfile -File ...`** |
| PS 5.1 đọc UTF-8 không có BOM → mojibake | Đọc/ghi file dùng `[System.IO.File]::ReadAllLines($p, [System.Text.Encoding]::UTF8)` |
| Console có thể hiển thị `—` thành `-` | Khi cần chắc chắn, in **codepoint** (`'{0:X4}' -f [int]$ch`), đừng tin mắt |
| `rg` không có; PowerShell 7.6.7 + Pester 6.2.0 | Dùng `Select-String` / `grep` tool |
| `.gitattributes`: `.md`/`.yml` LF, `.ps1` CRLF | Đừng commit warning CRLF |

Script điều tra tạm: `C:\Users\son\AppData\Local\Temp\opencode\*.ps1`.

## Quy ước commit / làm việc song song

- Prefix: `feat:` / `fix:` / `sync:` / `docs:` / `chore:` (mô tả tiếng Việt).
- **Trước khi sửa**: `git status` + `git diff` — session khác có thể đang giữ fix
  chưa commit (vụ 19/10: session song song đã vá `npm` trước).
- Không `git add` file WIP của người khác (`.env.sample`, `scripts/env/*`,
  `scripts/server/*`, `model-bank/modelbank.json`, `gen_xlsx.py`, `verify.py`).
- Chạy `pwsh scripts/test/Test-Suite.ps1` trước khi commit.

## Lệnh hay dùng

```powershell
mc validate | mc sync | mc prices | mc recommend | mc recommend -Apply
mc connectivity -Provider '1-xkiro-free' | mc benchmark ... | mc publish -ConnectivityTest
pwsh scripts/provider/Update-XKiroModels.ps1 -Recommend   # đồng bộ xKiro + ⭐
```
