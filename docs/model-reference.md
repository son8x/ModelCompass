# 🧭 Provider & Model — Tham chiếu cấu hình hiện tại

> **Canonical** — gắn trực tiếp với config repo: provider/model đang có, bảng ⭐
> (tự sinh + CI kiểm drift), quy ước thứ tự hiển thị, hạn mức & fallback xKiro.
>
> Phân tích **thị trường** (giá nhà cung cấp, cộng đồng, open-weight, so router,
> xu hướng, mẹo tiết kiệm) đã tách sang **[market-intel.md](market-intel.md)**.
> Giá thay đổi thường xuyên — luôn xác nhận lại trên trang chính thức trước khi trả phí.

---

## 1. Provider trong config hiện tại

> ⚠️ **Cách opencode 1.18.29 hiển thị danh sách trong `/model`** (source: `packages/tui/src/component/dialog-model.tsx`, hàm `sortModelOptions`):
> - **Nhóm provider**: sort theo **`name` A→Z** → phải đánh số `1.`, `2.`, … **ở đầu `name`** (và cả key `1-`, `2-`, …) mỗi provider để ép thứ tự.
> - **Model trong mỗi provider**: sort theo **`release_date` GIẢM DẦN**, rồi **`name` A→Z** — **KHÔNG giữ thứ tự khai báo**.
>   Nếu model không có `release_date`, thứ tự hiển thị rơi xuống `name` A→Z (đây là nguyên nhân "thứ tự không đúng" khi chỉ sắp lại trong file).

| # | Provider | Loại | Thế mạnh | Lưu ý |
|---|---|---|---|---|
| 1 | `1-xkiro-free` | Router free tier | Qwen, Cohere, Mistral | **51 model free** (16/10) — ⭐ theo tác vụ |
| 2 | `2-xkiro-max` | Router $20/tháng | Claude/GPT/Grok/GLM | **62 model**, 4 nhóm `[L]/[B]/[A]/[S]`, budget $264/tuần — ⭐ theo nhóm/tác vụ |
| 3 | `3-omniroute-free` | Route local | Cloudflare free (GLM-5.2, DeepSeek V4 Pro) | Cần local 127.0.0.1:20217 |
| 4 | `4-openrouter-free` | Route local | OpenRouter `:free` | 50 RPD, 1K nếu nạp $10 |
| 5 | `5-9router` | Router local | GPT-OSS 120B local | Cổng 20128 |
| 6 | `6-teamoRouter` | Router ưu đãi | GPU free + GPT/Claude giá rẻ | `TEAMO_API_KEY` |

---

## 2. ⭐ Model khuyến nghị xKiro (tự sinh)

<!-- BEGIN:recommend-stars — TỰ SINH bởi scripts/recommend/Update-RecommendDocs.ps1; ĐỪNG sửa tay (chạy `mc recommend-docs` để cập nhật) -->
> Cập nhật tự động: **20/10/2026** — **13 model** được khuyến nghị
> (7 free + 6 trả phí) — ⭐ ở đầu `name` trong `/model`. Sinh bởi
> `scripts/recommend/Update-RecommendDocs.ps1`; chạy `mc recommend-docs` để cập nhật.

**⭐ Theo nhóm** (⭐ = model mặc định nên chọn của nhóm):

| Nhóm | ⭐ Model | Giá in/out | Dùng cho |
|---|---|---|---|
| free | `qwen/qwen3.8-max:free` | free | reasoning (mặc định) |
| [L] Nhẹ·Nhanh·Rẻ | `nvidia/nemotron-3-nano-omni` | $0.05 / $0.20 | nhanh/subagent |
| [A] Mạnh đa dụng | `google/gemini-3.1-pro` | $2.00 / $12.00 | phân tích/nghiên cứu |
| [S] Flagship | `openai/gpt-6.1-sol` | $2.00 / $10.00 | flagship |

**⭐ Theo mục đích** (khớp đúng label trong `/model`):

| Mục đích | ⭐ Trả phí (`2-xkiro-max`) | ⭐ Miễn phí (`1-xkiro-free`) |
|---|---|---|
| reasoning (mặc định) | — | `qwen/qwen3.8-max:free` · 1M |
| code | `[A] x-ai/grok-4.7` · $2.00 / $6.00 | `qwen/qwen3-coder-plus:free` · 1M |
| phân tích/nghiên cứu | `[A] google/gemini-3.1-pro` · $2.00 / $12.00 | — |
| viết/văn phong | `[A] anthropic/claude-sonnet-5` · $2.00 / $10.00 | — |
| vision (hiểu ảnh) | `[A] google/gemini-3.8-flash` · $0.75 / $3.75 | `qwen/qwen3-vl-plus:free` · 262.1K |
| omni | — | `qwen/qwen3.8-omni-flash:free` · 1M |
| dịch | — | `cohere/command-a-translate` · 9K |
| nhanh/subagent | `[L] nvidia/nemotron-3-nano-omni` · $0.05 / $0.20 | `qwen/qwen3.5-flash:free` · 1M |
| soạn bài/PPTX | — | `mistralai/mistral-large-4-0` · 524.3K |
| flagship | `[S] openai/gpt-6.1-sol` · $2.00 / $10.00 | — |
<!-- END:recommend-stars -->

> **Lưu ý chọn model:**
> - Bulk đọc tài liệu / tạo slide (input chiếm ~85% chi phí) → chọn model **input ≤ $0.75 hoặc free**;
>   tránh `[S] claude-opus-5` ($5 in) nếu chỉ cần số lượng.
> - `mistralai/mistral-large-4-0` (free, 524K) = mặc định cho **soạn bài/PPTX** — đặt ở nhóm Mistral trong picker.
> - `cohere/command-a-reasoning` (free) hay **timeout >25s** → né khi cần phản hồi nhanh.
>
> Đề xuất theo hồ sơ người dùng (lập trình / luận văn / pentest / workload): [`recommendations/`](recommendations/README.md).

---

## 3. Quy ước thứ tự model trong `/model`

opencode dùng `release_date` của model làm **khoá sắp xếp chính** trong picker `/model`
(model có `release_date` LỚN hơn hiện TRƯỚC). Vì field này **không hiển thị ở bất kỳ đâu trên UI**,
ta dùng nó làm "khoá sắp xếp tổng hợp" — 2 provider xKiro hiện tại đã áp dụng:

- `1-xkiro-free` — **51 model free** (probe 16/10/2026): Qwen 19 · Cohere 16 · Mistral 9 · Meituan 2 · Meta 2 · Stealth 2 · SenseNova 1. Thứ tự **theo độ mạnh giảm dần** (Qwen3.8 Max trên cùng), `release_date` từ `2099-12-31` giảm dần → `2099-10-26`; `mistral-large-4-0` đặt ở **`2099-11-25`** (giữa nhóm Mistral). Lỗi còn lại: `cohere/command-a-reasoning` hay **timeout >25s**.
- `2-xkiro-max` — **62 model** dùng được trên gói Max (probe 15/10), hiển thị **theo 4 nhóm sức mạnh** rẻ-nhanh → mạnh nhất: `[L] Nhẹ·Nhanh·Rẻ` (26) → `[B] Đa dụng giá tốt` (11) → `[A] Mạnh đa dụng` (14) → `[S] Flagship` (11). `release_date` từ `2099-10-31` giảm dần → `2099-09-04`. Tag nhóm ngay trong `name` để nhận biết model **cùng tầng / thay thế được cho nhau**. Tên hiển thị ghi giá đầy đủ `In/Out` (USD/1M token) lấy từ catalog live — trên gói Max tính theo allowance $264/tuần (không trừ per-token), giá dùng để ước lượng khi nạp thêm wallet.

> 📌 Lịch sử thêm/gỡ model, danh sách model bị `403` (tính wallet / cần gói ≥ Ultra), model lỗi tạm
> (`⚠️`), và các đợt sync theo ngày: xem **[STATUS.md](../STATUS.md)** (mục "Lịch sử đáng nhớ").

**Quy ước đặt `release_date` tổng hợp khi cần kiểm soát thứ tự model:**

1. Model muốn hiện **trên** → gán `release_date` **lớn hơn** (vì opencode sort GIẢM DẦN).
2. Dùng vùng năm **`2099`** để phân biệt với ngày phát hành thật (không lẫn khi catalog ra model mới).
3. Danh sách N liên tiếp: sinh bằng helper (§3b) — `scripts\config\New-SortOrderKey.ps1 -Count N` (giảm dần từ `2099-12-31`, cách 1 ngày; `-From` để đổi điểm bắt đầu cluster). Khi **chèn mới vào giữa**: `-Between <key-trên> -BetweenLower <key-dưới>` — helper chọn ngày nằm giữa, không phải đụng date các model khác.
4. **Không trùng `release_date`** giữa 2 model — trùng sẽ rơi xuống sort theo `name` A→Z làm mất thứ tự.
5. Chỉ áp dụng cho provider muốn ép thứ tự model; provider không đặt `release_date` sẽ hiển thị theo `name` A→Z.
6. Schema hỗ trợ `release_date` ở mỗi model (`provider.<id>.models.<id>.release_date`, string) — xác nhận tại `https://opencode.ai/config.json`.
7. Sau khi sửa: validate → `Publish-Config.ps1` → `Install-Config.ps1` → **quit & restart opencode** (config chỉ nạp 1 lần lúc khởi động).

### 3b. Helper "khoá sắp xếp" (`scripts\config\New-SortOrderKey.ps1`)

Mọi việc bấm số `2099-…` giờ hội tụ về 1 helper (Phase 2.3) — **script chỉ IN key, không sửa file** (config chứa nhiều comment, tránh hỏng):

| Thao tác | Lệnh |
|----------|------|
| Sinh N key giảm dần (mặc định từ `2099-12-31`) | `pwsh scripts\config\New-SortOrderKey.ps1 -Count 24` |
| Sinh key cho cluster khác (vd cụm B trả phí, bắt đầu `2099-10-25`) | `pwsh scripts\config\New-SortOrderKey.ps1 -From 2099-10-25 -Count 9` |
| Chèn model giữa 2 model đã có (không đụng date khác) | `pwsh scripts\config\New-SortOrderKey.ps1 -Between <key-trên> -BetweenLower <key-dưới>` |
| Thêm N model vào cuối provider (tự đọc key nhỏ nhất, nối tiếp) | `pwsh scripts\config\New-SortOrderKey.ps1 -Append -Config <config> -Provider <id> -Count N` |
| Dựng lại toàn bộ key của provider | `pwsh scripts\config\New-SortOrderKey.ps1 -Rebuild -Config <config> -Provider <id> -From 2099-12-31` |

Helper tránh trùng key bằng `-Exclude` (tự động nạp key sẵn có trong `-Append`). Hàm thuần dùng chung:
`New-SortOrderKey` / `Get-SortOrderKeyBetween` trong `scripts\Common-Functions.ps1` (phủ test tại
`tests\SortOrder.Tests.ps1`).

> Cách thay thế (không khuyến khích): đánh số vào `name` ("01 · DeepSeek V4 Pro"…) cũng ép được thứ tự
> khi không có `release_date`, nhưng làm **nhiễu fuzzy search** (`fuzzysort` gõ chữ số) và hiển thị số xấu
> trong picker/badge — chỉ dùng khi buộc phải ưu tiên "minh bạch trong file".

---

## 4. xKiro — gói, hạn mức, chi tiêu

### xKiro Max — Chi tiết ($20/tháng)

- **Allowance** (trang chính thức mới nhất): **$264/tuần** cho model paid/premium — *con số đo được trước đây trong script là $140/tuần, có thể là mức cũ/promo; chạy lại `Get-XKiroUsage.ps1` để xác nhận*
- **1.8B token free/tháng** (~60M/ngày) cho model free — *tài liệu cũ ghi 32M/ngày, kiểm tra lại*
- Burst limit: $20/5 giờ
- Kiểm tra: `pwsh scripts\provider\Get-XKiroUsage.ps1`
- Theo dõi trong opencode: **status bar cuối màn hình** (TUI plugin `.opencode/plugins-xkiro/xkiro-statusline.tsx`, slot `app_bottom`) — **quota bar đa provider** (Phase 1.4): mặc định 1 dòng `quota · xKiro free 25.92M (19%) · burst $19.96 (0%) · budget $140.00 (0%) · wallet $0.00`, mở rộng thêm provider bằng `QUOTA_PROVIDERS=xkiro,teamo` (provider chưa có API quota → hiện `… chưa có quota API` màu thường, không phải lỗi). Tự làm mới theo chu kỳ và sau mỗi lượt trả lời, tổng tone lấy theo provider dùng nhiều nhất (vàng ≥90%, đỏ hết). Đi kèm plugin `.opencode/plugins-xkiro/xkiro-usage.js` ghi chi tiết xKiro vào `opencode.log` + toast cảnh báo ngưỡng (90%). Logic chung nằm ở `.opencode/plugins-xkiro/quota-common.js`. Biến: `XKIRO_STATUSBAR_DISABLE`, `XKIRO_STATUSBAR_RENDER_MS` (ms, mặc định 5000), `XKIRO_STATUSBAR_WARN_PCT`; `QUOTA_PROVIDERS`, `QUOTA_STATUSBAR_*`, `QUOTA_CACHE_DIR` (provider ngoài xKiro); `XKIRO_USAGE_DISABLE`, `XKIRO_USAGE_INTERVAL` (s, mặc định 300), `XKIRO_USAGE_WARN_PCT`, `XKIRO_USAGE_TOAST_EACH` (mặc định 1), `XKIRO_USAGE_TOAST_GAP` (s, mặc định 60), `XKIRO_USAGE_INJECT` (=1 mới ghi thêm vào transcript chat), `XKIRO_USAGE_INJECT_GAP` (s, mặc định 300).<br>**Lưu ý:** `ctrl+l` (`app_console`) là console debug của renderer, KHÔNG hiển thị log plugin — log chỉ ở file `opencode.log`.

### xKiro — Kiểm tra hạn mức, chi tiêu & ngày hết hạn gói

> Cập nhật **12/10/2026**. Nguồn: `docs.xkiro.com/api/usage/` + probe thực tế tài khoản.
> Cùng nguồn với plugin `.opencode/plugins-xkiro/` và `scripts\provider\Get-XKiroUsage.ps1`.

xKiro có **2 endpoint MIỄN PHÍ** (không tốn token, không tính allowance lẫn rate limit, không cần key trả phí):

| Endpoint | Trả về | Ghi chú |
|---|---|---|
| `GET /v1/usage` | `plan`, `windows[]` (`short` ~5h + `long` 7 ngày), `free_tokens` (ngày), `wallet` | Trả lời **"còn lại bao nhiêu"**. Field `plan`: chuỗi (vd `max`) = gói **đang hiệu lực**; **`null` = pay-as-you-go HOẶC gói đã kết thúc**. |
| `GET /v1/usage/history?period=day\|week\|month` | `points[]` (`requests`, `tokens`, `spend_usd`) + `total` | Trả lời **"đã dùng bao nhiêu"**. `day`=24 bucket giờ, `week`=7 ngày, `month`=30 ngày. `tokens` gộp cả **cache-read + reasoning** (không chỉ prompt+completion). |

- **KHÔNG có endpoint ngày hết hạn / billing.** Đã dò `/v1/me`, `/v1/subscription`, `/v1/account`, `/v1/billing`, `/v1/plan`, `/v1/user`, `/v1/limits`, `/openapi.json`, `/health` → **tất cả 404**. Tài liệu API chỉ liệt kê 2 endpoint trên.
- **`resets_in_sec`** của window `long` chỉ là **reset allowance 7 ngày**, **KHÔNG phải** ngày gói hết hạn — đừng nhầm.

**Xem ngày hết hạn / gia hạn gói ở đâu** (theo thứ tự ưu tiên):

1. **LemonSqueezy** — xKiro bán gói qua đây (kể cả subscription): email hóa đơn *"Your subscription to xKiro…"* hoặc cổng `https://app.lemonsqueezy.com/my-orders` → ghi **Next billing date** + nút Manage subscription (gia hạn/hủy/đổi gói).
2. **Console xKiro** — `https://xkiro.com/dashboard` (plan) · `https://xkiro.com/dashboard/api/usage` (chi tiêu per-key/model/day) · `https://xkiro.com/dashboard/api/keys`.

**Số đo thật** (12/10/2026, từ `/v1/usage/history`): **7 ngày $79.51** (1.986 req · 252M token) · **30 ngày $298.44** (8.297 req · 1.12B token) ≈ **$75/tuần**. Chi tiết 7 ngày: 06/10 **$30.37** · 07/10 **$23.28** · 08/10 **$25.86** → khớp ước tính DB (~$75–90/tuần).

```powershell
# allowance / burst / free-token còn lại (gọi /v1/usage)
pwsh scripts\provider\Get-XKiroUsage.ps1

# chi tiêu ĐÃ DÙNG (gọi /v1/usage/history — miễn phí)
$h = @{ Authorization = "Bearer $env:XTROUTER_API_KEY" }
Invoke-RestMethod "https://api.xkiro.com/v1/usage/history?period=week" -Headers $h
```

> Bảng gói xKiro (Pro/Pro+/Max/Ultra/Power) + so sánh router khác: [market-intel.md](market-intel.md) §8.

---

## 5. Fallback khi model xKiro Max bị overload (theo tầng)

> **Bản chất**: xKiro là proxy bán lại — upstream có giới hạn concurrent; model nào **"đáng tiền" nhất trong tầm giá** (giá/hiệu năng ngon) thì đông người dùng nhất → hay bị chạm hạn mức và trả `429 "temporarily at capacity"` / `500`. Không riêng nhóm A: B (giá rẻ) cũng bị ép.
> **Lưu ý**: catalog `GET /v1/models` **không có field availability** → không thể lọc trước khi chọn, phải dựa retry + fallback. Lỗi là **thoáng qua** (1 mình dùng thử lại sau vài giây thường OK). Probe snapshot 17/09/2026: `gpt-5.6-terra`/`gpt-5.6-luna` `500`, `kimi-k2.5` `429`; `glm-5.3`, `sonnet-5`, `gpt-5.5`, `opus-5`, `haiku-4.5` OK.
> **Quy tắc chọn**: ưu tiên (1) retry lại trong ~5–10s, (2) chuyển **Fallback cùng tầng** (giữ nguyên mức chất lượng, giá tương đương), (3) giảm chi phí → **Backup rẻ (B)**, (4) cần sức mạnh thật và chấp nhận giá → **Nâng cấp (S)**.

| Model chính (tầng chọn) | Fallback cùng tầng | Backup rẻ hơn | Nâng cấp mạnh hơn |
|---|---|---|---|
| `z-ai/glm-5.3` (A) | `claude-sonnet-5` / `gpt-5.6-terra` | `glm-5.3-flash` / `gpt-5.6-luna` (L) | `claude-opus-5` / `claude-fable-5` (S) |
| `claude-sonnet-5` (A) | `gpt-5.6-terra` / `glm-5.3` | `claude-haiku-4.5` / `gpt-5.6-luna` (L) | `claude-opus-5` (S) |
| `google/gemini-3.8-flash` (A) | `gemini-3.7-flash` / `gemini-3.1-pro` | `glm-5.3-flash` / `gemini-3-flash` (L) | `claude-opus-5` (S) |
| `gpt-5.6-terra` (A) | `gemini-3.1-pro` / `glm-5.3` | `glm-5.3-flash` (L) | `claude-opus-5` / `gpt-5.5` (S) |
| `openai/gpt-5.4` (A) | `claude-sonnet-5` / `gpt-5.6-terra` | `gpt-5.4-mini` (L) | `claude-opus-5` / `claude-fable-5` (S) |
| `z-ai/glm-5.2` (B) | `glm-5.3` (A) | `glm-5.3-flash` (L) | `claude-opus-4.8` / `claude-opus-5` (S) |
| `google/gemini-2.5-pro` (B) | `gemini-3-flash` (B) | `gemini-2.5-flash` (L) | `claude-opus-5` / `gpt-5.6-sol` (S) |
| `openai/gpt-5.6-luna` (L) | `glm-5.3-flash` (L) | `glm-4.6v-flash` / `claude-haiku-4.5` (L) | `glm-5.3` / `gpt-5.6-terra` (A) |

> **Đã gỡ khỏi danh sách (403 — không dùng được trên gói Max):** `kimi-k2.5/k2.6/k2.7-code/k3`, `grok-4.5/4.6/build-0.1`, `deepseek-v4-*`, `qwen3.5+/3.6+/3.7±/3.8-max`, `minimax-m2.5/m2.7/m3`, `tencent-hy3/hy4`, `xiaomi-mimo*`, `gpt-6-astra`, `claude-fable-5-1` — các model này nay tính phí theo **wallet (pay-as-you-go)** hoặc yêu cầu gói ≥ Ultra/Power, gói Max ($20/tháng) không phủ.

---

## 6. Free model cho review luận văn

Danh sách free model xKiro cho review luận văn (pass tổng thể / chấm câu / vision bảng biểu /
paraphrase) nằm ở hồ sơ người dùng: [recommendations/thesis-writing.md](recommendations/thesis-writing.md)
và [recommendations/lecturer-workload.md](recommendations/lecturer-workload.md).
