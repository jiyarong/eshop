# AI V2 SKU 竞品数据上传 API

## 请求

```http
POST /ai/v2/skus/competitor_data_batches
Authorization: Bearer <user_api_key>
Content-Type: multipart/form-data
Accept: application/json
```

- `sku_code` 必填，输入会去除首尾空格并转成大写。
- API Key 所属用户必须拥有 `manage_skus` 权限。
- `competitors` 必填，每个批次必须包含 5 到 8 条竞品数据。
- 每条竞品数据必须包含非空的 `markdown` 和恰好 4 个 `images[]` 文件。
- 服务端会校验并读取图片内容，不信任上传者声明的 MIME 类型。
- 每条数据的 4 张图片会按 2×2 白底版式合并为一张 2400×2400 JPEG，并通过 Active Storage 上传；production 环境使用七牛服务。
- 任一图片处理、文件上传或数据库写入失败时，本批次不会创建，已上传的本批次图片会被清理。

multipart 字段结构：

```text
sku_code
competitors[0][markdown]
competitors[0][images][]  # 重复 4 次
competitors[1][markdown]
competitors[1][images][]  # 重复 4 次
...
```

`curl` 示例（示例只展开第一条；实际请求需要提交 5–8 条）：

```bash
curl -X POST "https://<host>/ai/v2/skus/competitor_data_batches" \
  -H "Authorization: Bearer <user_api_key>" \
  -H "Accept: application/json" \
  -F "sku_code=SKU001" \
  -F "competitors[0][markdown]=# Competitor A" \
  -F "competitors[0][images][]=@./a-1.jpg" \
  -F "competitors[0][images][]=@./a-2.jpg" \
  -F "competitors[0][images][]=@./a-3.jpg" \
  -F "competitors[0][images][]=@./a-4.jpg"
```

## 成功响应

```json
{
  "data": {
    "id": 42,
    "sku_code": "SKU001",
    "competitor_count": 5,
    "created_at": "2026-09-10T12:00:00Z"
  }
}
```

响应状态为 `201 Created`。`id` 是本次竞品抓取批次 ID。

## 错误响应

| 状态 | `error` | 含义 |
| --- | --- | --- |
| `400` | `sku_code is required` / `competitors is required` | 缺少必填参数 |
| `401` | `Unauthorized` | API Key 缺失、无效或没有报表查看权限 |
| `403` | `Forbidden` | API Key 用户没有 SKU 管理权限 |
| `404` | `SKU not found` | SKU 不存在 |
| `422` | `competitors_count_must_be_between_5_and_8` | 批次不是 5–8 条 |
| `422` | `markdown_is_required` | 某条 Markdown 为空 |
| `422` | `images_count_must_be_4` | 某条图片数量不是 4 |
| `422` | `invalid_image` | 某个上传项不是可读取的图片 |
