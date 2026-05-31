# 商品管理 API（Content）

**Base URL**: `https://content-api.wildberries.ru`  
**Token 类别**: Контент（内容）  
**限流**: 100 req/min，600ms 间隔，Burst 5

---

## 一、分类与属性

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/content/v2/object/parent/all` | 获取所有父级分类（如电子产品、家用化学品） |
| GET | `/content/v2/object/all` | 获取所有子分类（предмет），支持按名称搜索，分页 |
| GET | `/content/v2/object/charcs/{subjectId}` | 获取某子分类的全部属性（名称、数据类型、单位等） |
| GET | `/content/v2/directory/colors` | 颜色字典 |
| GET | `/content/v2/directory/kinds` | 性别字典 |
| GET | `/content/v2/directory/countries` | 产地国字典 |
| GET | `/content/v2/directory/seasons` | 季节字典 |
| GET | `/content/v2/directory/vat` | 增值税率字典 |
| GET | `/content/v2/directory/tnved` | ТНВЭД 海关编码字典 |
| GET | `/api/content/v1/brands` | 品牌列表 |

**响应结构（分类）**:
```json
{
  "data": [
    { "id": 1, "name": "Электроника" }
  ],
  "error": false,
  "errorText": ""
}
```

**响应结构（属性）**:
```json
{
  "data": [
    {
      "charcID": 100,
      "name": "Цвет",
      "required": true,
      "unitName": "",
      "maxCount": 1,
      "popular": true,
      "charcType": 1
    }
  ]
}
```

---

## 二、商品卡片（карточки товаров）

创建流程：父分类 → 子分类 → 选属性 → 生成条码 → 创建卡片

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/content/v2/cards/limits` | 卡片数量限额 |
| POST | `/content/v2/barcodes` | 生成条码（barcode） |
| POST | `/content/v2/cards/upload` | 创建商品卡片 |
| POST | `/content/v2/cards/upload/add` | 创建卡片并关联已有卡片（换色款等） |
| POST | `/content/v2/get/cards/list` | 获取商品卡片列表（分页游标） |
| GET | `/content/v2/cards/error/list` | 获取创建失败的卡片列表及错误信息 |
| POST | `/content/v2/cards/update` | 编辑商品卡片 |
| POST | `/content/v2/cards/moveNm` | 合并/分拆卡片（nmID 迁移） |
| POST | `/content/v2/cards/delete/trash` | 将卡片移入回收站 |
| POST | `/content/v2/cards/recover` | 从回收站恢复卡片 |
| POST | `/content/v2/get/cards/trash` | 获取回收站中的卡片列表 |

**商品卡片核心字段**:
```json
{
  "nmID": 12345678,          // WB 平台商品编号（系统生成）
  "imtID": 87654321,         // 商品组 ID（同款不同色共用）
  "vendorCode": "MY-SKU-001", // 卖家自定义 SKU
  "brand": "MyBrand",
  "title": "Футболка мужская",
  "description": "...",
  "subjectID": 105,           // 子分类 ID
  "subjectName": "Футболки",
  "photos": [...],
  "video": {...},
  "dimensions": { "length": 10, "width": 8, "height": 2 },
  "characteristics": [
    { "id": 100, "name": "Цвет", "value": ["Красный"] }
  ],
  "sizes": [
    {
      "chrtID": 99887766,    // 规格 ID（每个 SIZE 独立）
      "techSize": "XL",
      "wbSize": "52",
      "skus": ["4607133781434"]  // 条码
    }
  ]
}
```

---

## 三、媒体文件

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/content/v3/media/file` | 上传图片/视频文件 |
| POST | `/content/v3/media/save` | 通过 URL 链接批量上传媒体 |

---

## 四、标签（Ярлыки）

用于商品搜索分组管理。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/content/v2/tags` | 获取标签列表 |
| POST | `/content/v2/tag` | 创建标签 |
| PUT | `/content/v2/tag/{id}` | 修改标签 |
| DELETE | `/content/v2/tag/{id}` | 删除标签 |
| POST | `/content/v2/tag/nomenclature/link` | 将标签添加/移除到商品卡片 |

---

## 五、价格与折扣

**Base URL 切换**: 价格接口使用 `https://discounts-prices-api.wildberries.ru`

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/api/v2/upload/task` | 批量设置价格和折扣（创建任务） |
| POST | `/api/v2/upload/task/size` | 按尺码设置价格 |
| POST | `/api/v2/upload/task/club-discount` | 设置 WB Club 折扣 |
| GET | `/api/v2/history/tasks` | 查询已处理的价格上传任务状态 |
| POST | `/api/v2/history/goods/task` | 获取已处理任务的商品明细 |
| GET | `/api/v2/buffer/tasks` | 查询待处理的价格上传任务 |
| POST | `/api/v2/buffer/goods/task` | 获取待处理任务的商品明细 |
| POST | `/api/v2/list/goods/filter` | 查询商品价格（按筛选条件） |
| POST | `/api/v2/list/goods/size/nm` | 查询商品各尺码价格 |
| POST | `/api/v2/quarantine/goods` | 查询被隔离（异常价格）的商品 |

**价格字段**:
```json
{
  "nmID": 12345678,
  "price": 1999,          // 含折扣前价格（RUB）
  "discount": 30,         // 折扣百分比
  "clubDiscount": 10      // WB Club 额外折扣（%）
}
```

---

## 六、仓库与库存（卖家仓 FBS/DBS）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v3/offices` | 获取 WB 仓库列表（官方仓） |
| GET | `/api/v3/warehouses` | 获取卖家仓库列表 |
| POST | `/api/v3/warehouses` | 创建卖家仓库 |
| PUT | `/api/v3/warehouses/{warehouseId}` | 更新卖家仓库信息 |
| DELETE | `/api/v3/warehouses/{warehouseId}` | 删除卖家仓库 |
| GET | `/api/v3/dbw/warehouses/{warehouseId}/contacts` | 获取仓库联系人 |
| PUT | `/api/v3/dbw/warehouses/{warehouseId}/contacts` | 更新仓库联系人 |
| PUT | `/api/v3/stocks/{warehouseId}` | 更新库存数量 |
| DELETE | `/api/v3/stocks/{warehouseId}` | 清空库存 |
| POST | `/api/v3/stocks/{warehouseId}` | 获取库存数量（按 SKU 列表） |

**库存字段**:
```json
{
  "stocks": [
    {
      "sku": "4607133781434",  // 条码
      "amount": 100            // 在仓数量
    }
  ]
}
```
