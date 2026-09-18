---
layout: page
title: Model catalog (theo giá / tác vụ)
---

Toàn bộ model trong **Model Bank**. Sort mặc định theo `releaseDate` giảm dần
(key 2099 do helper sort-order sinh ra — xem `docs/providers-and-models.md §6b`).

## Bảng model

| Provider | Model | Release | Giá name (In/Out) | Giá catalog (In/Out) | Preset |
|---|---|---|---|---|---|
{% assign sorted = site.data.modelbank.models | sort: 'releaseDate' | reverse %}
{% for m in sorted %}
| `{{ m.provider }}` | `{{ m.id }}` | {{ m.releaseDate }} | {% if m.pricing %}${{ m.pricing.input }} / ${{ m.pricing.output }}{% else %}-{% endif %} | {% if m.catalogPricing %}${{ m.catalogPricing.input }} / ${{ m.catalogPricing.output }}{% else %}-{% endif %} | {% if m.tags.size > 0 %}{{ m.tags | join: ', ' }}{% else %}-{% endif %} |
{% endfor %}

Xem hướng dẫn cạnh tranh: [README](https://github.com/son8x/ModelCompass).