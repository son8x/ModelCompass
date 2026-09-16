# Provider & Model — Phân tích (ảnh chụp Q3-2026)

> ⚠️ **Bản quyền dữ liệu**: giá API thay đổi thường xuyên. Bảng dưới là ảnh
> chụp thu thập giữa 07–09/2026; nguồn được ghi kèm. Trước khi trả phí luôn
> xác nhận lại trên trang chính thức của provider.

**Phạm vi bài viết này:** đối chiếu **giá/1 triệu token** (input | output),
**context window**, **tốc độ tương đối**, và **mức độ phù hợp** theo tác vụ.
Phần provider "route" (Teamorouter, OmniRoute, OpenRouter, xKiro, 9Router) được
phân tích riêng vì chúng là những nguồn đang được mô tả trong `configs/`.

---

## 1. Tóm tắt nhanh (Top picks 09/2026)

| Nhu cầu | Khuyến nghị | Lý do |
|---|---|---|
| Code agent mạnh | Claude Sonnet 5 (`$2/$10`), DeepSeek V4 Pro (`$0.435/$0.87`) | quality/số tiền/1 triệu token; Sonnet 5 có 1M context không phụ phí |
| Code miễn phí, nhanh | Groq Qwen3.8 27B, North Mini Code (OpenRouter free) | latency thấp, chất lượng code tốt |
| Viết luận văn / văn phong hàn lâm | Claude Sonnet 5, GLM-5.3 | tiếng Việt mượt, tổng hợp tài liệu tốt |
| Pentest / reasoning sâu | DeepSeek V4 Pro, Claude Sonnet 5 | reasoning rẻ (DeepSeek) hoặc clone cẩn thận (Claude) |
| Chi phí thấp, volume cao | DeepSeek V4 Flash (`$0.14/$0.28`) | rẻ nhất trong nhóm "đủ mạnh" |
| Long context (1M) | Claude Sonnet 5, Gemini 3.1 Pro | không phụ phí trên 200K (Claude) |

---

## 2. Giá API theo tier (USD / 1 triệu token, chuẩn, không cache)

Bảng tổng hợp từ nhiều nguồn đối chiếu (07–09/2026) — giá này là **giá gốc
provider**, chưa kể khuyến mãi/route giảm giá.

| Model | Provider | Input | Output | Context | Ghi chú |
|---|---|---|---|---|---|
| GPT-5.6 Luna | OpenAI | $0.20 | $1.20 | 1.05M | giảm 80% từ 30/07/2026 |
| GPT-5.4 Nano | OpenAI | $0.20 | $1.25 | 400K | |
| Gemini 3.1 Flash-Lite | Google | $0.25 | $1.50 | 1M | rẻ nhất nhóm Tier-1 |
| DeepSeek V4 Flash | DeepSeek | $0.14 | $0.28 | 1M | cache-hit ~$0.003 — rẻ nhất thị trường |
| GPT-5.4 Mini | OpenAI | $0.75 | $4.50 | 400K | |
| Claude Haiku 4.5 | Anthropic | $1.00 | $5.00 | 200K | Claude rẻ nhất |
| Claude Sonnet 5 | Anthropic | $2.00 | $10.00 | 1M | giá khuyến mãi, giữ nguyên từ 11/08 |
| GPT-5.6 Terra | OpenAI | $2.00 | $12.00 | 1.05M | |
| Gemini 3.1 Pro | Google | $2.00 | $12.00 | 1M | gấp đôi trên 200K |
| GPT-5.4 | OpenAI | $2.50 | $15.00 | 1M | |
| Grok 4.5 | xAI | $2.00 | $6.00 | 256K | gấp đôi trên 200K |
| GPT-5.6 Sol | OpenAI | $5.00 | $30.00 | 1.05M | flagship OpenAI |
| Claude Opus 5 | Anthropic | $5.00 | $25.00 | 1M | |
| Claude Fable 5 | Anthropic | $10.00 | $50.00 | 1M | mạnh nhất, đắt nhất |
| DeepSeek V4 Pro | DeepSeek | $0.435 | $0.87 | – | SWE-bench ~80.6 |
| GLM-5.3 / GLM-5.2 | Z.AI | $1.40 | $4.40 | – | MIT weights (5.2) |
| Kimi K2.7 Code | Moonshot | $0.95 | $4.00 | 262K | coding chuyên biệt |
| MiniMax M3 | MiniMax | $0.30 | $1.20 | 1M | open-weight giá rẻ |
| Qwen3.5 Plus | Alibaba | $0.40 | $2.40 | 256K | |

*Nguồn: morphllm.com (07/2026), cloudzero.com (08–09/2026), layer3labs.io
(09/2026), pricepertoken.com, spheron.network (08/2026).*

### Đọc bảng đúng cách

- **Output đắt hơn input 3–6×** — với agent xuất ra nhiều token, "giá output"
  quyết định hoá đơn, không phải giá input.
- **Cache read** thường = 10% giá input (Anthropic/OpenAI) hoặc thấp hơn
  (DeepSeek ~2%): workload lặp prompt ổn định sẽ rẻ hơn rất nhiều.
- **Batch API** (chờ 24h) = 50% giá — phù hợp khi không cần thời gian thực.
- **Không có phụ phí long-context**: Anthropic (4.6 trở lên); OpenAI/Gemini/Grok
  **gấp đôi** giá khi prompt > 200K.

---

## 3. Model miễn phí & free tier

| Nguồn miễn phí | Model tiêu biểu | Đánh giá |
|---|---|---|
| Cloudflare Playground (qua OmniRoute) | GLM-5.2, DeepSeek V4 Pro, Kimi K2.7 Code, GPT-OSS 120B | ⭐ mạnh nhất hiện tại, chạy tốt (đã test) |
| Groq | Qwen3.8 27B, GPT-OSS 120B, Llama 4 | tốc độ cực cao, rate-limit |
| OpenRouter `:free` | North Mini Code, Ling 3.0 Flash, Nemotron 3 Super | free tier đa dạng, nhiều model |
| Google AI Studio | Gemini Flash / Flash-Lite (1M ctx) | free hàng ngày, dễ bắt đầu |
| xKiro `:free` | MiniMax M2.x/M3 `:free`, DeepSeek V4 Pro/Flash, Mistral | multi-model free, đã test 'dùng được' |
| 9Router (local) | GPT-OSS 120B, Gemini Flash | chạy local qua router |
| Z.AI | GLM-5.3 Flash Free tier | tài khoản mới có free |

> ⚠️ **Cảnh báo free tier**: rate-limit dễ gây "ảnh hưởng công việc"; một số nhà
> cung cấp **tự chuyển sang ghi nợ (metered) âm thầm khi free credit hết** —
> đừng để key free tiếp xúc production traffic mà không có giới hạn chi tiêu.

---

## 4. Phân tích theo tiêu chí chọn model

### Giá rẻ nhất — "đủ mạnh để dùng"
`DeepSeek V4 Flash ($0.14/$0.28)` là nhà vô địch giá. Đứng thứ hai về rẻ là
`GPT-5.6 Luna`, nhưng **output** của Luna ($1.20) vẫn đắt gấp ~4× Flash —
với tác vụ sinh nhiều text (viết luận văn/exploit script lâu) DeepSeek thắng.

### Coding / agent
- Mạnh nhất: **Claude Sonnet 5 / Opus 5** (agent mỗi task tốn 400K–2M token input
  → Sonnet 5 với cache + 1M context là định mức tốt).
- Giá rẻ + khá: **DeepSeek V4 Pro** (~80.6 SWE-bench), **GLM-5.3**, **Kimi K2.7 Code**.
- Miễn phí nhanh: **Groq GPT-OSS/Qwen**, **North Mini Code**.

### Reasoning chuyên sâu (phân tích mạch, pentest)
`DeepSeek V4 Pro` rẻ gấp ~10× Claude khi reasoning dài; `Claude Opus 4.8` hoặc
`Gemini 3.1 Pro` khi độ chính xác tuyệt đối ưu tiên hàng đầu. Budget: `GLM-5.3 Flash`.

### Long context (đọc toàn bộ repo / cả luận văn)
- `Claude Sonnet 5`: 1M context **không phụ phí**.
- `Gemini 3.1 Pro`: 1M context, nhưng giá nhân đôi trên 200K.
- `GPT-5.6 Terra/Luna`: 1.05M context, phụ phí trên ~272K.

---

## 5. Các provider trong cấu hình hiện tại

> 🎯 **Thứ tự hiển thị trong `/model` = thứ tự khai báo trong
> `configs/*/opencode.json(c)`** — opencode giữ nguyên thứ tự khai báo của
> các provider tự cấu hình (không phải danh sách "Popular" có sẵn), nên
> **không cần đánh số** trước tên provider. Muốn đổi thứ tự ưu tiên chỉ cần
> kéo lên/xuống block, không phải sửa số. Thứ tự ưu tiên hiện tại:

| # | Provider (trong configs) | Loại | Thế mạnh | Lưu ý |
|---|---|---|---|---|
| 1 | `xkiro-free` | Router thương mại free tier | MiniMax `:free`, DeepSeek, Mistral | key `XTROUTER_API_KEY`; model `qwen:free` đã bị gỡ (404) từ 16/09 |
| 2 | `xkiro-max` | Router thương mại gói Max ($20/tháng) | Claude/GPT/Grok/GLM/Kimi/Nemotron tier paid | key `XTROUTER_API_KEY`; gemini/qwen-max/kimi-k3 cần wallet, gpt-6-astra cần Ultra/Power |
| 3 | `omniroute-free` | Route local (OmniRoute) | tận dụng Cloudflare/Groq free | cần local service 127.0.0.1:20217 |
| 4 | `openrouter-free` | Route local (OmniRoute→OpenRouter) | model `:free` OpenRouter | một số model báo `credits_exhausted` khi gọi paid song vẫn cho `:free` dùng |
| 5 | `9router` | Router local | GPT-OSS 120B local | cổng 20128; phụ thuộc máy chạy 9Router |
| 6 | `teamoRouter` | Router thương mại giá ưu đãi | GPU phổ (free) + GPT/Claude giá rẻ | key `TEAMO_API_KEY`; giá trong "name" đã bao gồm ưu đãi |

### Đánh giá theo hiệu quả giá (đã test thực tế — xem `STATUS.md`)
- **Miễn phí ổn định nhất**: `omniroute-free` (Cloudflare) — GLM-5.2, DeepSeek
  V4 Pro, Kimi K2.7 Code.
- **Tốc độ tốt nhất / token**: Groq Qwen3.8 27B (nhóm free).
- **Toàn diện + tầm giá trung bình**: TeamoRouter DeepSeek V4 / GPT-5.6 Luna.
- **Sang trọng**: Claude Sonnet 5 (thesis + code), Gemini 3.1 Pro (2M context).

### 5.1 xKiro Max — chi tiết gói ($20/tháng) & cơ chế $140/tuần

> Ảnh chụp 16/09/2026 từ `xkiro.com/#pricing` + `docs.xkiro.com/guides/pricing`.
> Trước khi chi lớn luôn xác nhận lại trong dashboard hoặc `GET /v1/models`.

Gói **Max** = $20/tháng, phủ **toàn bộ model tier `paid` + `free` + `premium`**
(~97 model chat trong catalog). Tier `premium` (flagship) chỉ mở sau khi tài
khoản **thanh toán thật** — gói trả phí như Max đạt điều kiện. Trong
`opencode.jsonc` dùng qua provider **`xkiro-max`**, model ID dạng
`vendor/model` (vd `anthropic/claude-opus-5`).

**Hạn mức của gói Max:**

| Hạn mức | Giá trị |
|---|---|
| Budget tier paid — **weekly** | **$140/tuần** (long window rolling 7 ngày) |
| Budget tier paid — **short** | cửa sổ rolling ~5 giờ → chặn burst (cap nhỏ hơn) |
| Free-model tokens | +960M token/tháng (~32M/ngày, chia theo rolling 24h) |
| Image gen | tính **wallet** riêng, không nằm trong $140/tuần |
| TTS | 148 giọng, miễn phí trong plan |
| Giá trị tối đa dùng được | ~$600/tháng ("worth up to 30×") |
| Concurrent / priority | tăng hơn Pro+; “Developer productivity tools”; email 24h |

**$140/tuần là gì và chạy ra sao:**

- **Không phải $140 nạp tiền** — là **allowance chi tiêu** cho các model
  paid/premium đã nằm sẵn trong giá gói $20/tháng. Bạn trả $20, được dùng sức
  tính tương đương ~$140/tuần (~$600/tháng).
- Tính theo **2 cửa sổ rolling** (`GET /v1/usage` trả `windows[]`): cửa sổ
  ngắn ~5 giờ (chặn burst) và cửa sổ dài 7 ngày (~$140). Mỗi request trừ đúng
  giá model bạn gọi; usage trong cửa sổ nằm trong plan.
- Hết cửa sổ **ngắn** → request bị từ chối (429) dù $140/tuần vẫn còn — chờ cửa
  sổ trôi qua. Cửa sổ **lăn**, không reset theo lịch cố định.
- **Free-model và paid-model là 2 ngân sách độc lập**: cạn free-token không đụng
  $140/tuần và ngược lại.
- Kiểm tra real-time: `curl https://api.xkiro.com/v1/usage -H "Authorization:
  Bearer $XKIRO_API_KEY"` → `windows[].spent_usd/cap_usd/remaining_usd/resets_in_sec`,
  `free_tokens.remaining`, `wallet.balance_usd`. Hoặc dashboard
  `xkiro.com/dashboard/api/usage`.

**Cách dùng trong ModelCompass:**

- Task rẻ/cao tần → giữ **`xkiro-free/*`** (DeepSeek/MiniMax/Mistral free):
  không tốn $140/tuần.
- Task quan trọng (review/chỉnh luận văn) → đổi `"model":
  "xkiro-max/<model-id>"`. Đọc cả luận văn (~200K token in, ~20K out):

  | Model (trong gói Max) | $/lượt cả luận văn | Lượt / tuần trong $140 |
  |---|---|---|
  | `openai/gpt-5.6-luna` | ~$0.03 | ~4.600 |
  | `anthropic/claude-sonnet-5` | ~$0.54 | ~260 |
  | `anthropic/claude-opus-5` | ~$1.35 | ~100 |

- ⚠️ **Ngoài gói** (đã test thực tế, xem note cứng config dòng 113–115 — cần
  nạp wallet hoặc gói Ultra/Power): `google/gemini-*`, `qwen/qwen3.7-max`,
  `minimax/minimax-m3`, `moonshotai/kimi-k3`, `moonshotai/kimi-k2.7-code`,
  `deepseek/deepseek-v4-pro-0813`, `deepseek/deepseek-v4.1-flash`,
  `openai/gpt-6-astra`.
- ⚠️ `qwen3.8-max`: trang delegate báo giá $2/$6 nhưng `/deals` quảng cáo
  “miễn phí” — kiểm tra thực tế trước khi gọi (có thể nằm ngoài plan, cần wallet).

### 5.2 Free model tốt nhất từ gói Max cho review luận văn

> Danh sách khớp với `xkiro-free` trong config (đã ping thực tế OK 16/09/2026).
> Tiêu chí chọn: **context dài** (đọc cả chương/luận văn), **tiếng Việt/văn phong
> hàn lâm**, **reasoning** để soi logic lập luận — model thuần code/thuần vision
> không được ưu tiên cho tác vụ này.

**Xếp hạng theo vai trò trong quy trình review:**

| # | Model (trong gói free) | Context | Vai trò / khi nào dùng | Lý do |
|---|---|---|---|---|
| 1 | `deepseek/deepseek-v4-pro` | 1.05M | **Pass tổng thể / chính**: đánh giá cấu trúc, logic, tính nhất quán toàn luận văn | reasoning mạnh nhất nhóm free, context 1M đọc cả luận văn 1 lượt |
| 2 | `deepseek/deepseek-v4-flash` | 1.05M | **Pass nhanh / chấm câu, lỗi lặp từ, style**: duyệt bản nháp nhiều lần | nhanh, vẫn đủ reasoning, cùng context 1M |
| 3 | `minimax/minimax-m3:free` | 1M | **Kiểm tra bảng/biểu/định dạng** (có vision) + pass dài | vision + reasoning + context 1M mà miễn phí |
| 4 | `minimax/minimax-m2.7:free` | 205K | **Review theo chương** khi cần văn phong chuẩn hơn, ít tiếng nói "AI" | open-weight cân bằng tiếng Việt tốt |
| 5 | `mistralai/mistral-large-2512` | 256K | **Viết lại đoạn / paraphrase** (bám sát văn phong gốc) | Mistral Large giữ nguyên ý khi diễn đạt lại |
| 6 | `deepseek/deepseek-v3.2` / `deepseek/deepseek-chat-v3.1` | 131–164K | Backup / cắt ngắn từng phần khi hết pool | dự phòng, không cần thiết lắm |

**Quy trình gợi ý (dùng mỗi bước một model khác nhau):**

1. **Soi cấu trúc + logic** toàn luận văn → `deepseek-v4-pro` (1 lượt, context 1M).
2. **Sửa chi tiết từng chương** (câu, chuyển ý, mạch lạc, tham khảo) →
   `deepseek-v4-flash` (lặp nhiều lượt, rẻ/nhanh).
3. **Rà bảng số liệu, biểu đồ, định dạng** → `minimax-m3:free` (vision).
4. **Viết lại những đoạn bị đánh giá "thiếu mượt"** → `mistral-large-2512`.

**Sức chứa của free pool:** 1 lượt đọc+soát cả luận văn ~200K input + ~30K output
≈ 230K token → với ~32M token/ngày, dư sức quét cả luận văn **~140 lượt/ngày**
mà không tốn $140/tuần. Nếu muốn "chuẩn hàn lâm thật sự" cho những đoạn quyết
điểm thì mới nên chuyển `xkiro-max/anthropic/claude-sonnet-5` (chất lượng, có phí).

---

## 6. Subscription vs API (khi nào trả phí?)

| Hình thức | Chi phí | Phù hợp |
|---|---|---|
| Claude Pro | $20/tháng (Claude Code included) | dev solo, dùng < 5 task/ngày |
| Claude Max 5x | $100/tháng | dev fulltime ~5 task/ngày |
| Codex Plus / Pro | $20 → $100 | việc trong hệ OpenAI |
| Copilot Enterprise | $39/ghế | đội ngũ flat-rate |
| API theo token | $3–600/tháng tuỳ model | tự automate, kiểm soát ngân sách |

> Quyết định nhanh: nếu trung bình >1 bug-fix ~$0.5-0.9/task, **subscription
> sớm hoà vốn** (Pro ~ $20 hoà vốn sau ~22-37 task). API thắng khi workload
> thấp + cần routing đa model (đúng nghĩa "ModelCompass").

---

## 7. Xu hướng & rủi ro cần theo dõi

- **Cuộc chiến $2/input**: Sonnet 5, Terra, Gemini 3.1 Pro đều neo $2 — so sánh
  bằng **output price + cache + context** thay vì sticker price.
- **Open-weight giá rẻ** (DeepSeek, GLM, MiniMax, Qwen) chèn mạnh vào phân khúc
  $0.1–0.5. Nếu dữ liệu nhạy cảm → cân nhắc tự host (chỉ rẻ khi >~30M token/ngày).
- **Free tier thay đổi đột ngột** — luôn test lại trước mỗi chu kỳ release.
- Tokenizer mới của Claude (4.7+) tạo **~30% token hơn** cho cùng văn bản —
  so sánh giá phải tính cả hiệu ứng tokenizer.

---

*Cập nhật lần cuối: 16/09/2026. Dữ liệu giá mới nhất nên được đối chiếu tại
trang chính thức từng provider trước khi quyết định trả phí.*