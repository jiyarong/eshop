# 用户沟通 API（User Communication）

**Base URL**: `https://feedbacks-api.wildberries.ru`  
**Token 类别**: Вопросы и отзывы（问答）  
**限流**:
- Personal/Service: 3 req/sec，Burst 6
- Basic: 5 req/hour

---

## 一、问题（Вопросы）

买家在商品页提出的问题。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/new-feedbacks-questions` | 是否有未读评价/问题（返回 true/false） |
| GET | `/api/v1/questions/count-unanswered` | 未回复问题数量（总计 + 今日） |
| GET | `/api/v1/questions/count` | 按时间段统计问题数量 |
| GET | `/api/v1/questions` | 问题列表（分页，最多10000条） |
| PATCH | `/api/v1/questions` | 回复/标记问题 |
| GET | `/api/v1/question` | 获取单个问题详情（按 ID） |

**问题字段**:
```json
{
  "id": "uuid",
  "wasViewed": false,
  "isAnswered": false,
  "nmId": 12345678,
  "productDetails": {
    "nmId": 12345678,
    "imtName": "Название товара",
    "supplierArticle": "MY-SKU"
  },
  "text": "Какой размер посоветуете?",
  "createdDate": "2024-01-15T10:00:00Z",
  "answer": {
    "text": "Рекомендуем размер М",
    "createDate": "2024-01-15T11:00:00Z",
    "editable": true
  }
}
```

---

## 二、评价（Отзывы）

买家购买后提交的评价（含星级评分）。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/feedbacks/count-unanswered` | 未回复评价数量 |
| GET | `/api/v1/feedbacks/count` | 按时间段统计评价数量 |
| GET | `/api/v1/feedbacks` | 评价列表（分页） |
| PATCH | `/api/v1/feedbacks/answer` | 回复评价 |
| PATCH | `/api/v1/feedbacks/answer` | 编辑已有回复 |
| GET | `/api/v1/feedbacks/order/return` | 按评价 ID 查询退货信息 |
| GET | `/api/v1/feedback` | 获取单个评价详情 |
| GET | `/api/v1/feedbacks/archive` | 归档评价列表 |

**评价字段**:
```json
{
  "id": "uuid",
  "wasViewed": false,
  "isAnswered": false,
  "productValuation": 5,    // 星级 1-5
  "createdDate": "2024-01-15T10:00:00Z",
  "text": "Отличный товар!",
  "productDetails": {
    "nmId": 12345678,
    "imtName": "Футболка",
    "supplierArticle": "MY-SKU",
    "size": "XL"
  },
  "answer": {
    "text": "Спасибо за отзыв!",
    "createDate": "...",
    "editable": true
  },
  "photo": [...],
  "video": [...]
}
```

---

## 三、置顶评价（Закреплённые отзывы）

卖家可以将优质评价置顶显示（有数量限制）。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/feedbacks/v1/pins` | 获取已置顶/已取消置顶的评价列表 |
| POST | `/api/feedbacks/v1/pins` | 置顶评价 |
| DELETE | `/api/feedbacks/v1/pins` | 取消置顶 |
| GET | `/api/feedbacks/v1/pins/count` | 置顶/非置顶数量统计 |
| GET | `/api/feedbacks/v1/pins/limits` | 置顶数量限制 |

---

## 四、买家聊天（Chat）

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/seller/chats` | 获取聊天列表 |
| GET | `/api/v1/seller/events` | 获取聊天事件（消息/状态变化） |
| POST | `/api/v1/seller/message` | 发送消息 |
| GET | `/api/v1/seller/download/{id}` | 下载消息中的文件 |

---

## 五、退货（Возвраты）

处理买家主动发起的退货申请。

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/v1/claims` | 获取退货申请列表 |
| PUT | `/api/v1/claim` | 回应退货申请（批准/拒绝） |

**退货申请字段**:
```json
{
  "claimID": "uuid",
  "status": "pending",      // pending, approved, rejected
  "createdDate": "2024-01-15T10:00:00Z",
  "reason": "Не подошел размер",
  "orderID": 987654321,
  "nmID": 12345678
}
```
