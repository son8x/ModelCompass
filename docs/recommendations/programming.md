# 💻 Lập trình — chọn model

Bối cảnh: code hàng ngày, sửa lỗi, refactor, đọc hiểu repo, viết script.
Tần suất cao → ưu tiên **giá/token + tốc độ**, đánh đổi nhẹ độ "thông minh".

## Top pick

| Mức | Model ID (provider/model) | Giá (~/1M) | Khi nào dùng |
|---|---|---|---|
| 🏆 Miễn phí + nhanh | `3-omniroute-free/groq/qwen/qwen3.8-27b` | $0 | fix lỗi, script, đọc repo vừa |
| 🏆 Miễn phí + mạnh | `3-omniroute-free/cfp/zai-org/glm-5.2` | $0 | feature vừa, refactor |
| 🏆 Trả phí rẻ | `6-teamoRouter/deepseek-v4-flash` | ~$0.14/$0.28 | code chất lượng, giá rẻ nhất |
| 🏆 Trả phí mạnh | `6-teamoRouter/claude-sonnet-5` | ~$2/$10 | agent/refactor lớn cần chính xác |
| ⚡ Tốc độ tối đa | `4-openrouter-free/openrouter/cohere/north-mini-code:free` | $0 | câu hỏi nhỏ, cần phản hồi dưới vài giây |

## Dự phòng

- `3-omniroute-free/cfp/deepseek-ai/deepseek-v4-flash-0731` — DeepSeek free qua Cloudflare.
- `6-teamoRouter/gpt-5.6-luna` — OpenAI rẻ ($0.20/$1.20) khi cần hệ GPT.
- `3-omniroute-free/groq/openai/gpt-oss-120b` — open-weight 120B trên Groq.
- `6-teamoRouter/deepseek-v4-pro` — khi cần suy luận sâu hơn (debug khó).

## Gợi ý thiết lập opencode

```jsonc
// trong development/opencode.jsonc
"model": "6-teamoRouter/deepseek-v4-flash",      // mặc định code chính
"small_model": "4-openrouter-free/openrouter/cohere/north-mini-code:free" // việc nhỏ
```

## Chi phí thực tế (ước tính 2026)

- Thread "bug-fix điển hình" với DeepSeek V4 Pro ≈ **$0.05–0.21/lần**.
- Với Claude Sonnet 5 ≈ **$0.54–2.28/lần** (nhưng tỉ lệ fix đúng cao hơn).
- Ai đọc repo lớn/agent dài → ưu tiên 1M context của Sonnet 5 để giảm lần nạp lại.

## Lưu ý

- Đổi **model mặc định** theo task: task đơn giản dùng `small_model`, task sâu
  dùng model chính.
- Model free bị rate-limit: nếu công việc dồn dập, chuyển hẳn sang DeepSeek/Luna
  trả phí rẻ để không mất thời gian chờ.