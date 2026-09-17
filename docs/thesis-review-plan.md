# Luận văn — Kế hoạch review & model phù hợp (gói xKiro Max)

> Gói **Max $20/tháng** (budget $140/tuần). Mọi model bên dưới lấy từ provider
> `2-xkiro-max` trong config; id đầy đủ dùng kiểu `2-xkiro-max/<id>` khi đặt
> model mặc định. Giá `In/Out` đối chiếu catalog xKiro 17/09/2026.
> Mục đích tệp này: map **từng tác vụ review luận văn → model nên dùng** + kịch
> bản thực hiện, để khỏi phải nhớ mỗi lần vào `/model`.

## 1. Bảng tác vụ → model

| # | Tác vụ trong review luận văn | Model đề xuất (`2-xkiro-max/<id>`) | Lý do |
|---|---|---|---|
| 1 | **Lập kế hoạch review / phác thảo tiêu chí chấm theo từng chương** | `anthropic/claude-sonnet-5` | Theo dõi yêu cầu dài, lập kế hoạch có cấu trúc, 1M ctx |
| 2 | **Đọc toàn bộ bản thảo → đánh giá mạch lạc, cấu trúc, trùng lặp** | `openai/gpt-5.6-terra` | Sustained context 1M giá rẻ, vision đọc bảng, review cả file không vỡ ngữ cảnh |
| 3 | **Sửa văn phong/câu từ từng chương (EN academic)** | `anthropic/claude-sonnet-5` | Chất lượng viết + giữ giọng văn nhất nhóm, 1M ctx |
| 4 | **Sửa văn phong tiếng Việt** | `z-ai/glm-5.3` | Tiếng Việt mạnh nhất nhóm, 1M ctx, rẻ |
| 5 | **Quét nhanh chính tả, ngữ pháp, định dạng, trích dẫn** | `openai/gpt-5.6-luna` | Reasoning + vision rẻ nhất paid, 1M ctx — chạy nhiều lượt không tốn |
| 6 | **Rà số liệu, bảng biểu, kiểm tra tính nhất quán số** | `moonshotai/kimi-k2.6` | 262K ctx, vision, bám theo chuỗi số liệu dài; rẻ hơn Claude cùng trọng số |
| 7 | **Biện luận sâu chương trọng tâm (phần đóng góp mới)** | `anthropic/claude-opus-5` | Reasoning flagship Anthropic, chất lượng phân biện tốt nhất |
| 8 | **Giả lập hội đồng đánh giá / chống-feedback** | `openai/gpt-5.6-sol` hoặc `anthropic/claude-opus-5` | Dùng luân phiên 2 flagship để có 2 góc nhìn khác nhau |
| 9 | **Background đọc hiểu tài liệu giá≈0 (không chi tiền)** | `deepseek/deepseek-v4-pro` (nhóm `1-xkiro-free`) | Miễn phí, 1M ctx — đọc nhanh để hiểu ngữ cảnh trước khi sửa |

## 2. Tác vụ NHỮNG model KHÔNG nên dùng

- `GLM-5 / 5.1 / 5.2` — **không có vision**: bỏ qua khi cần đọc bảng/biểu.
- `x-ai/grok-build-0.1` — **không reasoning**: chỉ tác vụ agent thao tác file.
- `anthropic/claude-fable-5` — mạnh nhất nhưng `$9/$45` — chỉ khi bản thảo cực khó, thường thay bằng Opus 5 rẻ hơn hẳn.
- `nvidia/nemotron-3-nano` — chỉ tóm tắt nhanh/minh họa, không dùng cho sửa văn bản nghiêm túc.

## 3. Kịch bản review theo giai đoạn

1. **Kickoff (Sonnet 5)**: nạp toàn bộ bản thảo + yêu cầu lập checklist tiêu chí theo từng chương (cấu trúc, luận điểm, trích dẫn, số liệu).
2. **Review tổng thể (Terra)**: đọc nguyên file 1 lượt → báo các điểm vỡ mạch lạc, chương thừa/thiếu, trùng lặp nội dung.
3. **Sửa chi tiết từng chương (Sonnet 5; GLM-5.3 nếu viết tiếng Việt)**: sửa từng đoạn giữ nguyên ý, giữ giọng văn.
4. **Rà số liệu + bảng (Kimi K2.6)**: so khớp số liệu trong text vs bảng biểu vs phụ lục.
5. **Quét lỗi nhẹ lần cuối (Luna)**: chính tả, punctuation, citation style, lặp từ.
6. **Chương trọng tâm (Opus 5)**: phản biện luận điểm chính, yêu cầu phản bác.
7. **Hội đồng giả lập (Sol ↔ Opus 5)**: đóng vai 2-3 thành viên hội đồng chấm, liệt kê câu hỏi có thể hỏi + lỗ hổng cần vá.

## 4. Chi phí ước tính (bản thảo ~100 trang, 1 lượt toàn bộ)

Giả định 100 trang ≈ 50–60K token in + 50–60K token out:

| Model | Chi phí 1 lượt ~ | Ghi chú |
|---|---|---|
| Luna | ≈ $0.04 | nhiều lượt thoải mái |
| Terra | ≈ $0.42 | 1 lượt review tổng thể |
| GLM-5.3 | ≈ $0.35 | chỉnh tiếng Việt |
| Sonnet 5 | ≈ $0.65 | sửa chi tiết |
| Opus 5 / Sol | ≈ $1.60 | chỉ chương trọng tâm |

Toàn bộ kịch bản mỗi vòng review ≈ **$4–6**, dư sức trong $140/tuần — có thể chạy nhiều vòng.

## 5. Cách dùng trong opencode

- **Đổi model mặc định cho phiên** (edit `model` trong config, mục `configs/development/opencode.jsonc`):
  ```
  "model": "2-xkiro-max/anthropic/claude-sonnet-5",
  ```
  rồi validate → `Publish-Config.ps1` → `Install-Config.ps1` → quit & restart.
- **Đổi model tạm trong một phiên chat**: dùng `/model` chọn tên model tương ứng (tên hiển thị có ghi giá + khuyến nghị).
- **Muốn dùng thử mà không đụng global**: `$env:OPENCODE_CONFIG = "D:\...\configs\development\opencode.jsonc"; opencode`.

## 6. Nhắc nhanh

- Viết tiếng Việt → GLM-5.3; viết tiếng Anh → Sonnet 5.
- Cần đọc bảng biểu → chọn model có vision (mọi model trong bảng trên trừ GLM-5.x đều có vision).
- Đọc hiểu không mất tiền → `deepseek/deepseek-v4-pro` (free, 1M ctx).
- Nếu sau này nâng gói **Ultra/Power ($100+)**: thêm `openai/gpt-6-astra` ($10/$50, 1.05M ctx) và `anthropic/claude-fable-5-1` ($10/$50) — là 2 flagship mạnh hơn cả Opus 5/Sol, chỉ dành cho chương quan trọng nhất.