# 📖 Viết luận văn — chọn model

Bối cảnh: viết văn hàn lâm **tiếng Việt**, tổng hợp lý thuyết, diễn giải thuật,
kiểm tra trích dẫn IEEE, định dạng HUTECH (Times New Roman 13, 1.5 dòng…), đọc
toàn bộ tài liệu dài (luận văn 5 chương, template).

➡️ Ưu tiên: **văn phong mượt + ngữ cảnh dài + chi phí hợp lý**, không cần
tốc độ cực nhanh.

## Top pick

| Mức | Model ID (provider/model) | Giá (~/1M) | Điểm mạnh |
|---|---|---|---|
| 🏆 Tổng hợp + văn phong | `teamoRouter/claude-sonnet-5` | ~$2/$10 | văn tiếng Việt tự nhiên, 1M context đọc cả chương, không phụ phí context dài |
| 🏆 Tiết kiệm | `teamoRouter/glm-5.3` | ~$1.40/$4.40 | tóm tắt và triển khai lý thuyết tốt |
| 🏆 Đọc cả luận văn | `teamoRouter/gemini-3.1-pro-preview` | ~$0.29/$1.73 | 2M context — nạp nguyên tài liệu + template |
| 🏆 Rà soát/copy-edit | `teamoRouter/gemini-3.5-flash-lite` | ~$0.30/$2.50 | kiểm tra lỗi chính tả, thống nhất mục lục, rẻ |

## Dự phòng

- `teamoRouter/gpt-5.6-terra` — session dài (viết liên tục nhiều giờ).
- `omniroute-free/cfp/zai-org/glm-5.2` — $0 khi tài chính eo hẹp, chất lượng khá.

## Gợi ý thiết lập opencode (cho dự án luận văn)

```jsonc
// dành riêng cho thư mục luận văn (project config .opencode/opencode.json)
"model": "teamoRouter/claude-sonnet-5",
"small_model": "teamoRouter/gemini-3.5-flash-lite"
```

## Quy trình viết luận văn với agent

1. **Chuẩn bị context**: để hướng dẫn định dạng (HUTECH) trong `CLAUDE.md` /
   `_TEMPLATE/FORMATTING_STANDARDS.md` như dự án hiện tại làm.
2. **Outline → Draft → Final** theo từng chương, yêu cầu agent dùng IEEE `[n]`
   và đánh số bảng/hình theo chương.
3. **Rà soát cuối**: dùng model rẻ (`flash-lite`) quét lỗi format, đếm trang,
   đối chiếu citation ↔ reference list.
4. **Tiết kiệm**: tác vụ lặp/đọc lại các chương đã viết → tận dụng **prompt
   cache** (cache read rẻ = 10% input) — cùng một agent session liên tục.

## Chi phí ước tính cho 1 luận văn (~100 trang)

- Chủ yếu Claude Sonnet 5 + rà soát flash-lite: **$15–40** cho toàn bộ quá trình
  viết + chỉnh sửa (nếu dùng API).
- Nếu dùng free (GLM-5.2/DeepSeek free): **$0–5**, chỉ tốn công sức prompt lại
  nhiều hơn.

## Lưu ý

- Model free tóm tắt dài có thể "mất mạch" — với nội dung học thuật, rải kiểm
  tra lại từng chương.
- Luôn kèm tài liệu chuẩn (template, quy định) trong context, không để agent tự
  đoán định dạng trường.