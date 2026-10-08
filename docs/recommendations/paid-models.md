# 💳 Model trả phí — phân tích & chọn mạnh/giá tốt

Tổng hợp **toàn bộ model trả phí** đang có trong cấu hình production
(`configs/production/opencode.json`) và đề xuất model **mạnh — giá tốt nhất
trong từng phân nhóm**.

➡️ Ưu tiên: **đúng tầng giá + đúng họ model**, tránh trả tiền cho model mà
router bán ngang/đắt hơn chính hãng.

> Giá = USD / 1 triệu token (input | output), snapshot theo config production.
> Giá thay đổi thường xuyên — xác nhận lại trước khi nạp tiền.

## 1. Tổng quan nguồn trả phí

| Provider | Kiểu trả phí | Số model | Phân nhóm |
|---|---|---|---|
| `2-xkiro-max` | Thuê bao **$20/tháng** (allowance ~$264/tuần) | 63 | 4 tầng `[L]`→`[B]`→`[A]`→`[S]` |
| `6-teamoRouter` | PAUG (trả theo token, giảm 70–90% Claude/GPT) | 10 (paid) | Claude / GPT / DeepSeek / Gemini / GLM |

## 2. `2-xkiro-max` — chọn model mạnh nhất trong từng tầng

> Vì đã trả thuê bao, các model `[A]/[S]` **không trừ token** trong allowance →
> ưu tiên dùng model mạnh; giá In/Out chỉ để ước lượng khi nạp thêm wallet.

| Tầng | Model mạnh–giá tốt nhất | Giá In/Out | Lý do |
|---|---|---|---|
| `[L]` Nhẹ/rẻ | **GPT-6 Luna** | $0.10/$0.50 | Reasoning + vision rẻ nhất, nhanh |
| `[L]` thay thế | GLM-5.3 Flash | $0.15/$0.50 | 1M + vision, code/tiếng Việt tốt |
| `[B]` Đa dụng rẻ | **MiMo V2.6 Pro** | $0.435/$0.87 | Rẻ ngang DeepSeek, 1M context |
| `[B]` thay thế | GLM-5.2 · Nemotron 3 Ultra | $0.25/$3.99 · $0.60/$2.40 | GLM rẻ input 1M; Nemotron mạnh |
| `[A]` Mạnh đa dụng | **GLM-5.3** / **Claude Sonnet 5** | $1.40/$4.40 · $2/$10 | GLM rẻ + tiếng Việt; Sonnet văn/agent đỉnh |
| `[A]` code agent | **GPT-5.6 Terra** | $1/$6 | Cân bằng, sustained context |
| `[S]` Flagship giá tốt | **GPT-6 Sol** | $2/$10 | "Flagship" nhưng ~1/2 giá Opus |
| `[S]` mạnh nhất | Claude Opus 5 / Opus 5.5 | $5/$25 · $4/$20 | Reasoning cao cấp khi cần rigor |

## 3. `6-teamoRouter` — chỉ dùng cho họ được giảm giá

| Họ | Model mạnh–giá tốt nhất | Giá In/Out | Lý do |
|---|---|---|---|
| Claude (rẻ nhất) | **Claude Sonnet 5** | $0.50/$2.52 | ~74% off, coding/văn đỉnh |
| Claude (siêu rẻ) | Claude Haiku 4.5 | $0.40/$2.00 | Routing / tác vụ nhẹ |
| GPT (rẻ nhất) | **GPT-5.6 Luna** | $0.11/$0.64 | Reasoning rẻ, ổn định |
| GPT (mini) | GPT-5.4 Mini | $0.09/$0.51 | Rẻ nhất còn mạnh |
| Reasoning dài | **GPT-5.6 Terra** | $0.27/$1.61 | Session viết dài |
| Gemini | **Gemini 3.1 Pro** | $0.29/$1.73 | 2M context, rẻ hơn chính hãng |
| DeepSeek | V4 Flash / V4 Pro | $0.14/$0.28 · $0.435/$0.87 | ⚠️ Xem cảnh báo bên dưới |
| GLM | GLM-5.3 | $1.40/$4.40 | ⚠️ Không giảm giá → bỏ qua |

> ⚠️ **Cảnh báo (docs/providers-and-models.md):** TeamoRouter bán **DeepSeek &
> GLM-5.3 ngang hoặc đắt ~2× chính hãng**. Với DeepSeek/GLM nên đi thẳng nguồn
> chính hoặc OpenRouter, đừng qua Teamo.

## 4. Chốt model theo tác vụ

| Nhu cầu | Chọn | Vì sao |
|---|---|---|
| Code agent hàng ngày | `6-teamoRouter/claude-sonnet-5` | ~$0.50/$2.52, ~90% chất lượng Opus |
| Volume lớn / rẻ nhất | `6-teamoRouter/deepseek-v4-flash` | $0.14/$0.28 |
| Viết luận văn (tiếng Việt) | `6-teamoRouter/claude-sonnet-5` | Văn phong mượt nhất |
| Pentest / reasoning sâu | `6-teamoRouter/deepseek-v4-pro` hoặc `2-xkiro-max/anthropic/claude-opus-5` | SWE-bench ~80.6% vs flagship |
| Cần frontier, đã có thuê bao | `2-xkiro-max/openai/gpt-6-sol` · `anthropic/claude-opus-5.5` | Nằm trong allowance $20/tháng |

## 5. Gợi ý thiết lập opencode

```jsonc
// mặc định code/viết — rẻ, mạnh
"model": "6-teamoRouter/claude-sonnet-5",
// tác vụ nhẹ/volume
"small_model": "6-teamoRouter/deepseek-v4-flash"

// khi cần sức mạnh frontier (đã bao trong thuê bao xKiro Max)
// "model": "2-xkiro-max/anthropic/claude-opus-5.5"
```

## 6. Lưu ý

- **Đọc sai nguồn giá tốn tiền**: họ Claude/GPT/Grok rẻ nhất ở TeamoRouter;
  họ DeepSeek/GLM/MiniMax rẻ nhất ở nguồn chính.
- **Thuê bao ≠ miễn phí token**: xKiro Max tính theo allowance ($264/tuần), vượt
  hạn mức mới trừ wallet — theo dõi qua status bar quota.
- Preset tương ứng: `configs/presets/fastest-paid.jsonc`, `thesis-writing.jsonc`,
  `pentest.jsonc`.
