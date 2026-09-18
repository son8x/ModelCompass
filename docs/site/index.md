---
layout: page
title: ModelCompass — tra cứu model AI
---

Dữ liệu tự sinh từ **Model Bank** (`model-bank/modelbank.json` — chạy `mc export`)
mỗi lần deploy; nguồn bản gốc là cấu hình `configs/production/opencode.json`
+ presets + catalog live trong repo.

## Giá /1M token

Giá hiển thị từ catalog live (`catalogPricing`) khi có, nếu không thì giá ghi
trong `name` config (`pricing`). Dấu `-` = provider không nhồi giá (thường free /
không thể so được). **Giá thay đổi thường xuyên — hãy xác nhận lại trên trang nhà cung cấp.**

## Tra cứu model

Xem bảng đầy đủ → [Model catalog](models.md).

## Provider đang quản lý

| # | Provider | Catalog | API key | Local |
|---|---|---|---|---|
{% for p in site.data.modelbank.providers %}
| `{{ p.id }}` | {{ p.name }} | {% if p.catalogId %}`{{ p.catalogId }}`{% else %}-{% endif %} | {% if p.apiKeyEnv %}`{{ p.apiKeyEnv }}`{% else %}-{% endif %} | {% if p.local %}🏠{% else %}☁️{% endif %} |
{% endfor %}

## Presets (model pick theo tác vụ)

| Preset | Số model | Đường dẫn |
|---|---|---|
{% for pr in site.data.modelbank.presets %}
| `{{ pr.name }}` | {{ pr.modelCount }} | `{{ pr.path }}` |
{% endfor %}

## Tài liệu

- [docs/](https://github.com/son8x/ModelCompass/tree/main/docs) — phân tích provider/model, workflow, recommendations, per-project config.
- [README](https://github.com/son8x/ModelCompass) — cài đặt, quickstart, `mc` CLI, benchmark.
- [ROADMAP](https://github.com/son8x/ModelCompass/blob/main/ROADMAP.md) / [CHANGELOG](https://github.com/son8x/ModelCompass/blob/main/CHANGELOG.md).

*Powered by ModelCompass — tìm đúng model, chạy đúng cấu hình.*