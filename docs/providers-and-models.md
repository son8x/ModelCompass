# Provider & Model Reference — Q3/2026

> **Giá thay đổi thường xuyên.** Luôn xác nhận lại trên trang chính thức trước khi trả phí.
> Đơn vị: **USD / 1 triệu token** (input | output).

---

## 1. Top Picks Nhanh

| Nhu cầu | Model | Giá | Lý do |
|---|---|---|---|
| Code agent mạnh nhất | Claude Opus 5 | $5 / $25 | SWE-bench top, 1M context, 128K output |
| Code agent giá tốt | DeepSeek V4 Pro | $0.435 / $0.87 | 80.6% SWE-bench, rẻ gấp 28× Opus |
| Code miễn phí, nhanh | Groq GPT-OSS 120B, Qwen3.8 27B | $0 | Tốc độ cực cao (2600 tok/s), rate-limit |
| Viết luận văn / văn phong | Claude Sonnet 5 | $2 / $10 | Tiếng Việt mượt, 1M context không phụ phí |
| Chi phí thấp, volume cao | DeepSeek V4 Flash | $0.14 / $0.28 | Rẻ nhất nhóm "đủ mạnh", 1M context |
| Long context (đọc cả repo) | Claude Sonnet 5, Kimi K3 | $2–3 / $10–15 | 1M context, không phụ phí trên 200K |
| Open-weight mạnh nhất | Kimi K3 | $3 / $15 | AA Index 57, #1 Frontend Coding, MIT |

---

## 2. Bảng Giá Tổng Hợp

### Frontier & Premium

| Model | Provider | Input | Output | Context | Ghi chú |
|---|---|---|---|---|---|
| Claude Fable 5 | Anthropic | $10.00 | $50.00 | 1M | Mạnh nhất, đắt nhất |
| Claude Opus 5 | Anthropic | $5.00 | $25.00 | 1M | Flagship Anthropic |
| GPT-5.6 Sol | OpenAI | $5.00 | $30.00 | 1.05M | Flagship OpenAI |
| Kimi K3 | Moonshot | $3.00 | $15.00 | 1M | Open-weight #1, MIT |
| GPT-5.5 | OpenAI | $5.00 | $30.00 | 1M | Terminal-Bench 93.9% |
| Grok 4.5 | xAI | $2.00 | $6.00 | 256K | Gấp đôi trên 200K |

### Mid-Tier (Giá trị tốt)

| Model | Provider | Input | Output | Context | Ghi chú |
|---|---|---|---|---|---|
| Claude Sonnet 5 | Anthropic | $2.00 | $10.00 | 1M | **Giá vĩnh viễn** (đã hủy tăng 09/2026) |
| GPT-5.6 Terra | OpenAI | $2.00 | $12.00 | 1.05M | Balanced |
| GPT-5.4 | OpenAI | $2.50 | $15.00 | 1M | |
| Gemini 3.1 Pro | Google | $2.00 | $12.00 | 1M | Gấp đôi trên 200K |
| GLM-5.3 | Z.AI | $1.40 | $4.40 | 1.3M | Open-weight, MIT |
| Claude Sonnet 4.6 | Anthropic | $3.00 | $15.00 | 1M | |
| Claude Haiku 4.5 | Anthropic | $1.00 | $5.00 | 200K | Claude rẻ nhất |

### Budget (Rẻ, vẫn dùng được)

| Model | Provider | Input | Output | Context | Ghi chú |
|---|---|---|---|---|---|
| DeepSeek V4 Pro | DeepSeek | $0.435 | $0.87 | 1M | 80.6% SWE-bench — **value king** |
| MiniMax M3 | MiniMax | $0.30 | $1.20 | 1M | Open-weight, vision + reasoning |
| GPT-5.6 Luna | OpenAI | $0.20 | $1.20 | 1.05M | Giảm 80% từ 07/2026 |
| Gemini 3.1 Flash-Lite | Google | $0.25 | $1.50 | 1M | Rẻ nhất nhóm Tier-1 |
| Qwen3.5 Plus | Alibaba | $0.40 | $2.40 | 256K | |
| Kimi K2.7 Code | Moonshot | $0.95 | $4.00 | 262K | Coding chuyên biệt |
| DeepSeek V4 Flash | DeepSeek | $0.14 | $0.28 | 1M | **Rẻ nhất thị trường**, cache-hit ~$0.003 |
| Claude Haiku 4.5 | Anthropic | $1.00 | $5.00 | 200K | Cache read $0.10 |

### Miễn phí

| Model | Provider | Context | Hạn mức | Ghi chú |
|---|---|---|---|---|
| GPT-OSS 120B | Groq | 131K | 30 RPM, 1K RPD | Tốc độ cực cao |
| Qwen3.8 27B | Groq | 8K | 60 RPM, 1K RPD | Nhanh, miễn phí |
| Llama 4 Scout | Groq | 131K | 30 RPM, 1K RPD | |
| GLM-5.2 | Cloudflare | 1M | 10K Neurons/ngày | Qua OmniRoute |
| DeepSeek V4 Pro | Cloudflare | 1M | 10K Neurons/ngày | Qua OmniRoute |
| Kimi K2.7 Code | Cloudflare | 1M | 10K Neurons/ngày | Qua OmniRoute |
| North Mini Code | OpenRouter | 256K | 50 RPD (1K nếu nạp $10) | |
| Nemotron 3 Ultra | OpenRouter | 1M | 50 RPD | NVIDIA, 550B MoE |
| Ling 3.0 Flash | OpenRouter | 262K | 50 RPD | |
| Gemini Flash | Google AI Studio | 1M | Theo tier | Free hàng ngày |

---

## 3. Phát Hiện Từ Cộng Đồng (Reddit, DEV, Benchmarks)

### Giá trị tốt nhất theo use-case (tổng hợp từ r/LocalLLaMA, r/ClaudeAI, r/AI_Agents, DEV.to, BenchLM)

| Use-case | Khuyến nghị cộng đồng | Lý do |
|---|---|---|
| Coding agent hàng ngày | **Claude Sonnet 5** ($2/$10) | 90% chất lượng Opus tại 1/5 giá, 1M context |
| Reasoning dài, pentest | **DeepSeek V4 Pro** ($0.435/$0.87) | Rẻ gấp 10–28× frontier, 80.6% SWE-bench |
| Routing / classification | **Haiku 4.5** hoặc **GPT-5.6 Luna** | Nhanh, rẻ, đủ thông minh để phân loại |
| Viết luận văn tiếng Việt | **Claude Sonnet 5** | Văn phong tự nhiên, không "giọng AI" |
| Multimodal (vision + text) | **MiniMax M3** ($0.30/$1.20) | Vision + reasoning + 1M context, giá rẻ |
| Tốc độ cao, demo | **Groq** (GPT-OSS 120B) | 2600 tok/s, miễn phí |
| Self-host / privacy | **GLM-5.2** (MIT, 753B) hoặc **Kimi K3** (MIT, 2.8T) | Open-weight, chạy local |

### Pattern phổ biến trong cộng đồng

1. **Model routing**: Haiku (phân loại) → Sonnet (thực thi) → Opus (planning)
2. **Cache aggressively**: System prompt trùng lặp → cache hit = giảm 90% chi phí input
3. **Batch API**: Không cần realtime → OpenAI/Anthropic giảm 50%
4. **DeepSeek cho volume**: Khi output > 10M token/tháng, DeepSeek V4 Pro tiết kiệm $240K/tháng so với Opus

---

## 4. Nguồn Miễn Phí Thông Dụng

| Nguồn | Model nổi bật | RPM | RPD | Lưu ý |
|---|---|---|---|---|
| **Groq** | GPT-OSS 120B, Qwen3.8 27B, Llama 4 | 30 | 1,000–14,400 | Nhanh nhất, không cần credit card |
| **OpenRouter `:free`** | 20+ model (Nemotron 3 Ultra, North Mini Code...) | 20 | 50 (1,000 nếu nạp $10) | Đa dạng nhất |
| **Cloudflare Workers AI** | GLM-5.2, DeepSeek V4 Pro, Kimi K2.7 Code | Không giới hạn | 10K Neurons/ngày | Privacy tốt |
| **Google AI Studio** | Gemini Flash (1M ctx) | Theo tier | Theo tier | Free hàng ngày, dễ bắt đầu |
| **NVIDIA NIM** | Kimi K3, DeepSeek V4 Flash, MiniMax M3 | ~40 | Theo model | 16 model miễn phí |
| **GitHub Models** | Nhiều model | 15 | 150 | Cần GitHub PAT |

> **Cảnh báo**: Free tier có thể thay đổi đột ngột. Luôn test lại trước mỗi chu kỳ production.

---

## 5. Open-Weight Models Mạnh Nhất (09/2026)

| Model | Params | AA Index | Context | Giá | License | SWE-bench |
|---|---|---|---|---|---|---|
| **Kimi K3** | 2.8T (104B active) | 57 (#4 global) | 1M | $3 / $15 | Modified MIT | #1 Frontend Coding |
| **GLM-5.3** | ~753B | 51 | 1.3M | $1.40 / $4.40 | MIT | 62.1% Pro |
| **MiniMax M3** | 428B (23B active) | 45 | 1M | $0.30 / $1.20 | MiniMax Community | 59.0% Pro |
| **DeepSeek V4 Flash** | 284B (13B active) | 72 | 1M | $0.14 / $0.28 | MIT | Agent-strong |
| **DeepSeek V4 Pro** | 1.6T (49B active) | 68.8 | 1M | $0.435 / $0.87 | MIT | **80.6%** |
| **Qwen3.8 Max** | 2.4T (95B active) | — | 1M | Preview |即将开源 | "Second to Fable 5" |

> **Xu hướng**: Open-weight đang closing gap với proprietary. Kimi K3 (AA Index 57) ngang Claude Opus 4.8. Lần đầu frontier-adjacent performance khả dụng off-cloud.

---

## 6. Các Provider Trong Config Hiện Tại

> ⚠️ **Cách opencode 1.18.29 hiển thị danh sách trong `/model`** (source: `packages/tui/src/component/dialog-model.tsx`, hàm `sortModelOptions`):
> - **Nhóm provider**: sort theo **`name` A→Z** → phải đánh số `1.`, `2.`, … **ở đầu `name`** (và cả key `1-`, `2-`, …) mỗi provider để ép thứ tự.
> - **Model trong mỗi provider**: sort theo **`release_date` GIẢM DẦN**, rồi **`name` A→Z** — **KHÔNG giữ thứ tự khai báo**.
>   Nếu model không có `release_date`, thứ tự hiển thị rơi xuống `name` A→Z (đây là nguyên nhân "thứ tự không đúng" khi chỉ sắp lại trong file).

| # | Provider | Loại | Thế mạnh | Lưu ý |
|---|---|---|---|---|
| 1 | `1-xkiro-free` | Router free tier | MiniMax `:free`, DeepSeek, Mistral | Free plan: 5M token/ngày + 40+ model free |
| 2 | `2-xkiro-max` | Router $20/tháng | Claude/GPT/Grok/GLM + $140/tuần | Premium tier mở sau khi trả tiền |
| 3 | `3-omniroute-free` | Route local | Cloudflare free (GLM-5.2, DeepSeek V4 Pro) | Cần local 127.0.0.1:20217 |
| 4 | `4-openrouter-free` | Route local | OpenRouter `:free` | 50 RPD, 1K nếu nạp $10 |
| 5 | `5-9router` | Router local | GPT-OSS 120B local | Cổng 20128 |
| 6 | `6-teamoRouter` | Router ưu đãi | GPU free + GPT/Claude giá rẻ | `TEAMO_API_KEY` |

### Thứ tự model trong `/models` — cách ép theo ý muốn

opencode dùng `release_date` của model làm **khoá sắp xếp chính** trong picker `/model`
(model có `release_date` LỚN hơn hiện TRƯỚC). Vì field này **không hiển thị ở bất kỳ đâu trên UI**,
ta dùng nó làm "khoá sắp xếp tổng hợp" — 2 provider xKiro hiện tại đã áp dụng:

- `1-xkiro-free` — 24 model, thứ tự **theo độ mạnh giảm dần** (DeepSeek V4 Pro trên cùng), `release_date` từ `2099-12-31` giảm dần → `2099-12-08`. Tên model ghi chú **thế mạnh/lĩnh vực** (thay cho chữ "Free" cũ), đối chiếu capabilities xKiro 17/09/2026. Model "đang 503 tạm": `gpt-5.3-codex-spark`, `sensenova-6.8-flash-lite`.
- `2-xkiro-max` — 25 model, hiển thị **theo nhóm sức mạnh** (rẻ → mạnh: `[B] Nhẹ/rẻ` → `[A] Mạnh đa dụng` → `[S] Flagship`), trong mỗi nhóm **giá input tăng dần** (rẻ trước). `release_date` từ `2099-10-25` giảm dần → `2099-10-01`. Tag nhóm + giá nằm ngay trong `name` để nhận biết model **thay thế được cho nhau** và giá khi chọn. Thành phần nhóm: `[B]` = Nemotron Nano/Super/Ultra, Luna, GLM-5.3 Flash, Kimi K2.5, Grok Build, GPT-5.4 Mini, Haiku 4.5; `[A]` = Kimi K2.6, Grok 4.6/4.5, GLM-5/5.1/5.2/5.3, GPT-5.6 Terra, GPT-5.4, Claude Sonnet 5/4.6; `[S]` = Opus 4.8/5, GPT-5.5/Sol, Fable 5. Giá `In/Out` đối chiếu `GET /v1/models` xKiro 17/09/2026. Loại khỏi danh sách: `gpt-6-astra`, `claude-fable-5-1` (API khai tier=paid nhưng thực tế cần gói ≥ Ultra, bị 403 trên gói Max).

**Quy ước đặt `release_date` tổng hợp khi cần kiểm soát thứ tự model:**

1. Model muốn hiện **trên** → gán `release_date` **lớn hơn** (vì opencode sort GIẢM DẦN).
2. Dùng vùng năm **`2099`** để phân biệt với ngày phát hành thật (không lẫn khi catalog ra model mới).
3. Danh sách N liên tiếp: sinh bằng helper (mục §6b) — `scripts\New-SortOrderKey.ps1 -Count N` (giảm dần từ `2099-12-31`, cách 1 ngày; `-From` để đổi điểm bắt đầu cluster). Khi **chèn mới vào giữa**: `-Between <key-trên> -BetweenLower <key-dưới>` — helper chọn ngày nằm giữa, không phải đụng date các model khác.
4. **Không trùng `release_date`** giữa 2 model — trùng sẽ rơi xuống sort theo `name` A→Z làm mất thứ tự.
5. Chỉ áp dụng cho provider muốn ép thứ tự model; provider không đặt `release_date` sẽ hiển thị theo `name` A→Z.
6. Schema hỗ trợ `release_date` ở mỗi model (`provider.<id>.models.<id>.release_date`, string) — xác nhận tại `https://opencode.ai/config.json`.
7. Sau khi sửa: validate → `Publish-Config.ps1` → `Install-Config.ps1` → **quit & restart opencode** (config chỉ nạp 1 lần lúc khởi động).

### 6b. Helper "khoá sắp xếp" (`scripts\New-SortOrderKey.ps1`)

Mọi việc bấm số `2099-…` giờ hội tụ về 1 helper (Phase 2.3) — **script chỉ IN key, không sửa file** (config chứa nhiều comment, tránh hỏng):

| Thao tác | Lệnh |
|----------|------|
| Sinh N key giảm dần (mặc định từ `2099-12-31`) | `pwsh scripts\New-SortOrderKey.ps1 -Count 24` |
| Sinh key cho cluster khác (vd cụm B trả phí, bắt đầu `2099-10-25`) | `pwsh scripts\New-SortOrderKey.ps1 -From 2099-10-25 -Count 9` |
| Chèn model giữa 2 model đã có (không đụng date khác) | `pwsh scripts\New-SortOrderKey.ps1 -Between <key-trên> -BetweenLower <key-dưới>` |
| Thêm N model vào cuối provider (tự đọc key nhỏ nhất, nối tiếp) | `pwsh scripts\New-SortOrderKey.ps1 -Append -Config <config> -Provider <id> -Count N` |
| Dựng lại toàn bộ key của provider | `pwsh scripts\New-SortOrderKey.ps1 -Rebuild -Config <config> -Provider <id> -From 2099-12-31` |

Helper tránh trùng key bằng `-Exclude` (tự động nạp key sẵn có trong `-Append`). Hàm thuần dùng chung:
`New-SortOrderKey` / `Get-SortOrderKeyBetween` trong `scripts\Common-Functions.ps1` (phủ test tại
`tests\SortOrder.Tests.ps1`).

> Cách thay thế (không khuyến khích): đánh số vào `name` ("01 · DeepSeek V4 Pro"…) cũng ép được thứ tự
> khi không có `release_date`, nhưng làm **nhiễu fuzzy search** (`fuzzysort` gõ chữ số) và hiển thị số xấu
> trong picker/badge — chỉ dùng khi buộc phải ưu tiên "minh bạch trong file".

### xKiro Max — Chi tiết ($20/tháng)

- **Allowance** (trang chính thức mới nhất): **$264/tuần** cho model paid/premium — *con số đo được trước đây trong script là $140/tuần, có thể là mức cũ/promo; chạy lại `Get-XKiroUsage.ps1` để xác nhận*
- **1.8B token free/tháng** (~60M/ngày) cho model free — *tài liệu cũ ghi 32M/ngày, kiểm tra lại*
- Burst limit: $20/5 giờ
- Kiểm tra: `pwsh scripts\Get-XKiroUsage.ps1`
- Theo dõi trong opencode: **status bar cuối màn hình** (TUI plugin `.opencode/plugins-xkiro/xkiro-statusline.tsx`, slot `app_bottom`) — **quota bar đa provider** (Phase 1.4): mặc định 1 dòng `quota · xKiro free 25.92M (19%) · burst $19.96 (0%) · budget $140.00 (0%) · wallet $0.00`, mở rộng thêm provider bằng `QUOTA_PROVIDERS=xkiro,teamo` (provider chưa có API quota → hiện `… chưa có quota API` màu thường, không phải lỗi). Tự làm mới theo chu kỳ và sau mỗi lượt trả lời, tổng tone lấy theo provider dùng nhiều nhất (vàng ≥90%, đỏ hết). Đi kèm plugin `.opencode/plugins-xkiro/xkiro-usage.js` ghi chi tiết xKiro vào `opencode.log` + toast cảnh báo ngưỡng (90%). Logic chung nằm ở `.opencode/plugins-xkiro/quota-common.js`. Biến: `XKIRO_STATUSBAR_DISABLE`, `XKIRO_STATUSBAR_RENDER_MS` (ms, mặc định 5000), `XKIRO_STATUSBAR_WARN_PCT`; `QUOTA_PROVIDERS`, `QUOTA_STATUSBAR_*`, `QUOTA_CACHE_DIR` (provider ngoài xKiro); `XKIRO_USAGE_DISABLE`, `XKIRO_USAGE_INTERVAL` (s, mặc định 300), `XKIRO_USAGE_WARN_PCT`, `XKIRO_USAGE_TOAST_EACH` (mặc định 1), `XKIRO_USAGE_TOAST_GAP` (s, mặc định 60), `XKIRO_USAGE_INJECT` (=1 mới ghi thêm vào transcript chat), `XKIRO_USAGE_INJECT_GAP` (s, mặc định 300).<br>**Lưu ý:** `ctrl+l` (`app_console`) là console debug của renderer, KHÔNG hiển thị log plugin — log chỉ ở file `opencode.log`.

### xKiro Max — Ứng cứu khi model bị overload (fallback theo tầng)

> **Bản chất**: xKiro là proxy bán lại — upstream có giới hạn concurrent; model nào **"đáng tiền" nhất trong tầm giá** (giá/hiệu năng ngon) thì đông người dùng nhất → hay bị chạm hạn mức và trả `429 "temporarily at capacity"` / `500`. Không riêng nhóm A: B (giá rẻ) cũng bị ép.
> **Lưu ý**: catalog `GET /v1/models` **không có field availability** → không thể lọc trước khi chọn, phải dựa retry + fallback. Lỗi là **thoáng qua** (1 mình dùng thử lại sau vài giây thường OK). Probe snapshot 17/09/2026: `gpt-5.6-terra`/`gpt-5.6-luna` `500`, `kimi-k2.5` `429`; `glm-5.3`, `sonnet-5`, `gpt-5.5`, `opus-5`, `haiku-4.5` OK.
> **Quy tắc chọn**: ưu tiên (1) retry lại trong ~5–10s, (2) chuyển **Fallback cùng tầng** (giữ nguyên mức chất lượng, giá tương đương), (3) giảm chi phí → **Backup rẻ (B)**, (4) cần sức mạnh thật và chấp nhận giá → **Nâng cấp (S)**.

| Model A (chính) | Fallback cùng tầng (A) | Backup rẻ (B) | Nâng cấp (S) |
|---|---|---|---|
| `kimi-k2.6` | `grok-4.6` | `glm-5.3-flash` / `kimi-k2.5` | `gpt-5.5` |
| `grok-4.6` | `grok-4.5` | `gpt-5.6-luna` | `gpt-5.6-sol` |
| `grok-4.5` | `grok-4.6` | `glm-5.3-flash` | `gpt-5.6-sol` |
| `glm-5` | `glm-5.1` / `glm-5.2` | `glm-5.3-flash` | `gpt-5.5` |
| `gpt-5.6-terra` | `grok-4.6` / `glm-5.3` | `gpt-5.6-luna` | `gpt-5.6-sol` |
| `glm-5.1` | `glm-5.2` / `glm-5.3` | `glm-5.3-flash` | `gpt-5.5` |
| `glm-5.2` | `glm-5.3` | `glm-5.3-flash` | `gpt-5.5` |
| `glm-5.3` | `claude-sonnet-5` / `grok-4.6` | `gpt-5.6-luna` / `glm-5.3-flash` | `claude-opus-5` |
| `claude-sonnet-5` | `gpt-5.4` / `gpt-5.6-terra` | `claude-haiku-4.5` / `gpt-5.6-luna` | `claude-opus-5` |
| `gpt-5.4` | `claude-sonnet-5` | `gpt-5.6-luna` | `claude-opus-5` |
| `claude-sonnet-4.6` | `claude-sonnet-5` | `gpt-5.6-luna` / `claude-haiku-4.5` | `claude-opus-5` |

### Free model tốt nhất từ xKiro cho review luận văn

| # | Model | Context | Vai trò |
|---|---|---|---|
| 1 | `deepseek/deepseek-v4-pro` | 1M | Pass tổng thể — reasoning mạnh nhất free |
| 2 | `deepseek/deepseek-v4-flash` | 1M | Pass nhanh, chấm câu, lỗi lặp |
| 3 | `minimax/minimax-m3:free` | 1M | Kiểm tra bảng/biểu (vision) |
| 4 | `mistralai/mistral-large-2512` | 256K | Viết lại đoạn / paraphrase |

---

## 7. Tips Tiết Kiệm

| Mẹo | Tiết kiệm | Áp dụng |
|---|---|---|
| **Cache system prompt** | 90% input cost | Prompt trùng lặp > 80% |
| **Batch API** (chờ 24h) | 50% tổng | Không cần realtime |
| **Model routing** | 50–80% | Task đơn giản → model rẻ |
| **DeepSeek thay Claude** | 10–30× | Volume coding, reasoning |
| **Free tier cho dev** | 100% | Groq + OpenRouter + Cloudflare |

### Subscription vs API

| Hình thức | Chi phí | Phù hợp |
|---|---|---|
| Claude Pro | $20/tháng | Dev solo, < 5 task/ngày |
| Claude Max 5x | $100/tháng | Dev fulltime |
| API theo token | $3–600/tháng | Tự automate, routing đa model |

> Quyết định nhanh: > 1 bug-fix ~$0.5–0.9/task → subscription sớm hoà vốn.

---

## 8. Xu Hướng Cần Theo Dõi

- **Cuộc chiến $2/input**: Sonnet 5, Terra, Gemini 3.1 Pro đều neo $2 → so sánh bằng output price + cache + context
- **Open-weight closing gap**: Kimi K3 (57 AA Index) ngang Opus 4.8 → frontier-adjacent khả dụng off-cloud
- **DeepSeek dominant value**: V4 Pro 80.6% SWE-bench tại 1/28 giá Opus — thay đổi kinh tế agent
- **Tokenizer mới Claude (4.7+)**: Tạo ~30% token hơn cho cùng văn bản → tính cả khi so sánh giá
- **Free tier thay đổi đột ngột**: Luôn test lại trước mỗi production cycle

---

## 9. Router & Gateway Providers (09/2026)

> Phân loại mô hình trả phí: **PAUG** = pay-as-you-go (trả theo token); **Thuê bao** = phí tháng, xài trong budget.

### Tổng quan nhanh

| Router | Trả phí | Model | Giảm giá | Free tier | Điểm mạnh |
|---|---|---|---|---|---|
| **TeamoRouter** | PAUG | 37+ (LLM24) | **70–90%** Claude/GPT/Grok | GPU + vài model free | Rẻ nhất nhóm frontier |
| **OpenRouter** | PAUG (+5.5% nạp) | 500+, 70+ provider | Giá chính hãng | 20+ model, 50 RPD (1K nếu nạp $10) | Catalog lớn nhất, chuẩn OpenAI |
| **xKiro** | Thuê bao | 105+, 16 provider | Budget rất lớn / $ | 40+ model free | Value subscription |
| **Hypereal AI** | Thuê bao (credit) | Claude/GPT/Gemini + image/video | 50–60% | — | Đa modal |
| **9Router** (local) | Tự chọn nguồn | 100+, 60+ provider | RTK nén 20–40% token | Kiro/OpenCode/Vertex | Open-source, MIT |
| **Vercel AI Gateway** | PAUG | Tất cả major | 0 markup | — | Đồng bộ interface |
| **Cloudflare AI Gateway** | PAUG | Tất cả major | 5% unified billing | Workers AI 10K Neurons/ngày | Privacy, free core |
| **CometAPI** | PAUG | 500+ | Phí reseller | — | Nhiều model |
| **AIHubMix** | PAUG | 849 | — | **48 model free** | Catalog free lớn nhất |
| **MAIA Router** | PAUG | LLM/media/embed | — | — | Thị trường Đông Nam Á |

### TeamoRouter — Giá model (so chính hãng)

| Model | TeamoRouter | Chính hãng | Giảm |
|---|---|---|---|
| Claude Opus 5 | $1.32 / $6.58 | $5 / $25 | ~74% |
| Claude Sonnet 5 | $0.52 / $2.58 | $2 / $10 | ~74% |
| Claude Haiku 4.5 | $0.14 / $0.70 | $1 / $5 | ~86% |
| Claude Fable 5 | $2.64 / $13.20 | $10 / $50 | ~74% |
| GPT-6 Astra | $1.09 / $5.45 | ~$10 / $50 | ~89% |
| GPT-5.6 Sol | $0.71 / $4.26 | $5 / $30 | ~86% |
| GPT-5.6 Terra | $0.26 / $1.54 | $2 / $12 | ~87% |
| GPT-5.6 Luna | $0.12 / $0.72 | $0.20 / $1.20 | ~40% |
| GPT-5.5 | $0.56 / $3.33 | $5 / $30 | ~89% |
| Grok 4.6 | $0.21 / $0.62 | $2 / $6 | ~90% |
| Kimi K3 | $2.29 / $11.46 | $3 / $15 | ~24% |
| GLM-5.3 | $1.40 / $4.40 | $1.40 / $4.40 | 0% |
| GLM-5.3 Flash | $0.07 / $0.24 | — | — |
| GLM-5.2 | $0.84 / $2.64 | $1.40 / $4.40 | ~40% |
| DeepSeek V4 Pro | $0.81 / $2.42 | $0.435 / $0.87 | **ĐẮT hơn ~2×** |
| DeepSeek V4 Flash | $0.30 / $0.89 | $0.14 / $0.28 | **ĐẮT hơn ~2×** |

**Chốt quan trọng:** TeamoRouter rẻ mạnh cho **Claude/GPT/Grok** (cache-optimized + reseller), nhưng **DeepSeek & GLM-5.3 ngang hoặc đắt hơn chính hãng** → model open-weight rẻ nên đi thẳng nguồn chính hoặc OpenRouter.

### xKiro — Gói thuê bao (trang chính thức)

| Gói | Giá | Token free/tháng | Budget/tuần | Giá trị tới |
|---|---|---|---|---|
| Pro | $5 | 450M | $67 | ~$287 |
| Pro+ | $10 | 900M | $132 | ~$565 |
| **Max** | **$20** | **1.8B** | **$264** | ~$1,131 |
| Ultra | $100 | 9B | $1,320 | ~$5,657 |
| Power | $200 | 18B | $2,640 | ~$11,314 |

- 105+ model, 16 provider, 1M+ context, 40+ model free; OpenAI + Anthropic SDK compatible
- Nạp thêm qua LemonSqueezy (credits $10+, subscription $5–1.920)
- ⚠ Có cả **kiro.dev** (tool IDE companion AWS, tính theo credit: Pro $19–20 = 1K credits, Pro Max $100 = 5K) — là sản phẩm KHÁC, xác minh cẩn thận trước khi nạp tiền.

### Đối thủ tương đương / rẻ hơn xKiro (09/2026)

| Provider | Mô hình | Giá / $ | Tương đương xKiro? | Rẻ hơn xKiro? |
|---|---|---|---|---|
| **LLM API** (llmapi.ai) | PAYG @ giá chính hãng (0 markup) + sub AI-for-Coding | PAYG free; Lite $30 / Pro $100 / Plus $200 | **CÓ** — 400+ model, 30+ provider, 1 key | **RẺ hơn khi rõ ràng**: token-pool minh bạch, volume discount 5–15%, nạp lần đầu **x2**, ~2× hạn mức so sub chính hãng |
| **ZenMux** | Thuê bao Pro/Max/Ultra + PAYG | Pro $20 / Max $100 / Ultra $400 | **CÓ** — 200+ model, 1 API | Ngang giá Pro $20; thêm giảm tới **80%** trên 10+ model phổ biến + **bảo hiểm AI** (tự hoàn credit khi lỗi/latency) + nạp 100 được 120 |
| **ClaudeAPI** (claudeapi.com) | PAYG, ~80% giá Claude chính hãng | Nạp trước, không cần card quốc tế | Một phần — chỉ Claude | Rẻ hơn Claude trực tiếp, không cap budget (khác xKiro: không có gói token free) |
| **Hypereal AI** | Credit (100cr = $1), sub | Theo credit | Một phần — 50+ model premium | Giảm 50–60% so chính hãng; mạnh về media (Nanobanana/Veo/Seedance), LLM chỉ kèm |
| **Kiro** (kiro.dev) | Free / $20–200 theo credit | Free 50cr (Claude Sonnet 4.5); Pro $20 = 1.000cr | Không — IDE companion, không phải router | Không so sánh trực tiếp được |
| **Opper** | PAYG, EU-hosted | Theo token | Khác tiêu chí | 700+ model, zero-retention — chỉ khi cần EU residency |
| **Together/Fireworks/DeepInfra** | PAYG open-weight | Theo token | Khác loại | **RẺ hơn hẳn** cho open-weight (gpt-oss-120B $0.15/$0.60, LFM2 24B $0.03/$0.12) |

**Chốt so sánh:** Ở mốc $20–30/tháng, nếu muốn **minh bạch** (biết chính xác mua được bao nhiêu token) → **LLM API Lite $30** (rõ token-pool từng model + x2 nạp đầu). Nếu muốn **giá/mô hình tương đương xKiro** với thêm lớp bồi hoàn → **ZenMux Pro $20**. Chỉ khi muốn **Claude/GPT/Grok rẻ từng đồng, trả theo token** → **TeamoRouter** (70–90% off).

### Khuyến nghị "model mạnh, giá tốt nhất"

| Nhu cầu | Chọn | Lý do |
|---|---|---|
| Claude/GPT/Grok giá rẻ nhất | **TeamoRouter** | Sonnet 5 $0.52/$2.58, Opus 5 $1.32/$6.58 |
| Code cả ngày, muốn subscription, giá trị lớn | **xKiro Max $20** | Budget $264/tuần, 1.8B token free/tháng |
| Subscription **minh bạch** (biết rõ mua gì) | **LLM API Lite $30** | Token-pool rõ từng model, x2 nạp đầu, không markup |
| Subscription + bồi hoàn | **ZenMux Pro $20** | Bảo hiểm AI, giảm tới 80% model hot |
| Nhiều model linh hoạt cho dự án | **OpenRouter** + **LLM API** | Catalog lớn nhất, trả theo token, không markup |
| Open-weight rẻ nhất | **Chính hãng trực tiếp** | DeepSeek/GLM/MiniMax — DeepSeek V4 Flash $0.14/$0.28 không router nào bán rẻ hơn |
| Muốn miễn phí hoàn toàn | **Groq + OpenRouter:free + Cloudflare + xKiro free** | 4 nguồn free bổ sung nhau |

---

*Cập nhật: 16/09/2026. Nguồn: anthropic.com, openai.com, deepseek.com, artificialanalysis.ai, costgoat.com, lmmarketcap.com, r/LocalLLaMA, r/ClaudeAI, DEV.to, freellm.net, openrouter.ai/pricing, teamorouter.com + llm24.net, kiro.dev, xkiro.com, llmapi.ai, zenmux.ai, gateway-llm.com.*
