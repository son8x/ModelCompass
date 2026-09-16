# 📊 STATUS — Trạng thái test từng model

> Duy trì bảng này mỗi lần publish/rollback. Ký hiệu:
> ✅ Đã test OK trên máy thật · 🧪 Đang thử · ❌ Lỗi/gỡ · ⏸️ Test lại khi giá/tier đổi

## Provider hiện có (production snapshot 16/09/2026)

| Provider | Mô hình | Trạng thái | Ghi chú |
|---|---|---|---|
| `xkiro-free` | Đủ 24 free model: MiniMax (M2→M3, 8 model), DeepSeek (5), Mistral (8), SenseNova (2), GPT-5.3 Codex Spark | ✅ | từ 16/09 bổ sung đủ catalog free; `sensenova-6.8-flash-lite` & `gpt-5.3-codex-spark` đang 503 tạm |
| `xkiro-max` | Claude Sonnet 5 / Opus 5 / Fable 5, GPT-5.6 Sol/Terra/Luna | 🧪 | gói Max ($20/tháng, từ 16/09); Anthropic/OpenAI đang 429 tạm (upstream quá tải) |
| `xkiro-max` | Grok 4.6/4.5, GLM-5.3/5.2/5.1/5, Kimi K2.6/2.5, Nemotron 3 Super/Ultra | ✅ | đã ping OK trên gói Max |
| `omniroute-free` | GLM-5.2, DeepSeek V4 Pro, Kimi K2.7 Code (Cloudflare) | ✅ | ⭐ mạnh nhất nhóm free |
| `omniroute-free` | GPT-OSS 120B, Qwen3 30B, Nemotron 3 (Cloudflare) | ✅ | tốt, dùng fallback |
| `omniroute-free` | Qwen3.8 27B / Qwen3.6 27B / GPT-OSS 120B (Groq) | ✅ | ⭐ nhanh nhất, rate-limit |
| `omniroute-free` | Gemini 3.1 Flash Lite / 2.5 Flash 8B | 🧪 | free daily, giới hạn theo ngày |
| `openrouter-free` | North Mini Code `:free` | ✅ | siêu nhanh, chuyên code |
| `openrouter-free` | Ling 3.0 Flash, Nemotron 3 Super, Laguna S `:free` | 🧪 | connection `credits_exhausted` khi gọi paid, `:free` vẫn OK |
| `9router` | GPT-OSS 120B, Gemini 3.8 Flash (local) | ⏸️ | phụ thuộc dịch vụ local 20128 |
| `teamoRouter` | DeepSeek V4 Flash Free / GLM-5.3 Flash Free | ✅ | miễn phí, dùng cho tác vụ lặp |
| `teamoRouter` | GPT-5.4 Mini / GPT-5.6 Luna | ✅ | rẻ nhất nhóm paid, tính năng ổn |
| `teamoRouter` | DeepSeek V4 Flash / V4 Pro | ✅ | flash nhanh, pro reasoning |
| `teamoRouter` | Claude Haiku 4.5 / Sonnet 5 | ✅ | haiku nhanh, sonnet agent/viết |
| `teamoRouter` | GLM-5.3 | 🧪 | cần đo lại giá/ổn định session dài |
| `teamoRouter` | GPT-5.6 Terra / Gemini 3.1 Pro | 🧪 | context dài, kiểm tra phụ phí >200K |

## Bị gỡ / không dùng

| Model/Provider | Lý do | Thời gian |
|---|---|---|
| Gemini 2.5 Flash (direct AI Studio) | `404` với user mới → chuyển sang Gemini 3.x | 09/2026 |
| deepinfra / siliconflow / sambanova | router thương mại trả phí, rủi ro nhầm model tính tiền | đã cân nhắc gỡ |

## Lịch sử đáng nhớ

- 16/09/2026 — Khởi tạo ModelCompass, snapshot production từ config đang chạy.

---

> Quy tắc cập nhật: ghi ✅ chỉ khi model đã chạy được ≥1 phiên đầy đủ trên
> opencode (không lỗi, tốc độ/giá như kỳ vọng). Ghi ❌ khi gỡ khỏi config.