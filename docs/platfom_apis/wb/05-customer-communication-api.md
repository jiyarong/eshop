# Wildberries Customer Communication API

> Base URLs:
> - Feedbacks & Questions: `https://feedbacks-api.wildberries.ru`
> - Buyers Chat: `https://buyer-chat-api.wildberries.ru`
> - Returns: `https://returns-api.wildberries.ru`

## Authentication

All endpoints use `HeaderApiKey` authentication. Tokens are category-specific:

| Category | Token Category |
|---|---|
| Questions / Feedbacks / Pinned Feedback | **Feedbacks and Questions** |
| Buyers Chat | **Buyers Chat** |
| Buyers Returns | **Buyers Returns** |

---

## 1. Questions

### 1.1 Unseen Feedbacks and Questions

```
GET /api/v1/new-feedbacks-questions
```

**Description:** Returns whether the seller has unseen feedbacks and questions.

**Parameters:** None

**Response 200:**
```json
{
  "data": {
    "hasNewQuestions": true,
    "hasNewFeedbacks": false
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 401, 402, 403, 429

---

### 1.2 Unanswered Questions Count

```
GET /api/v1/questions/count-unanswered
```

**Description:** Returns the number of unanswered questions for today and for all time.

**Parameters:** None

**Response 200:**
```json
{
  "data": {
    "countUnanswered": 24,
    "countUnansweredToday": 0
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 401, 402, 403, 429

---

### 1.3 Number of Questions

```
GET /api/v1/questions/count
```

**Description:** Returns the number of questions for the requested period.

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `dateFrom` | integer | No | — | Start date, Unix timestamp |
| `dateTo` | integer | No | — | End date, Unix timestamp |
| `isAnswered` | boolean | No | `true` | `true` = answered, `false` = not answered |

**Response 200:**
```json
{
  "data": 77,
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 400, 401, 402, 403, 429

---

### 1.4 Questions List

```
GET /api/v1/questions
```

**Description:** Returns paginated questions list (max 10,000 per query). Total of `take` + `skip` ≤ 10,000.

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `isAnswered` | boolean | **Yes** | — | `true` = answered, `false` = not answered |
| `take` | integer | **Yes** | — | Number of questions to return (max 10,000) |
| `skip` | integer | **Yes** | — | Number of questions to skip (max 10,000) |
| `nmId` | integer | No | — | WB item number (SKU) |
| `order` | string | No | — | Sort: `dateAsc` / `dateDesc` |
| `dateFrom` | integer | No | — | Start date, Unix timestamp |
| `dateTo` | integer | No | — | End date, Unix timestamp |

**Response 200:**
```json
{
  "data": {
    "countUnanswered": 24,
    "countArchive": 508,
    "questions": [
      {
        "id": "2ncBtX4B9I0UHoornoqG",
        "text": "Question text",
        "createdDate": "2022-02-01T11:18:08.769513469Z",
        "state": "suppliersPortalSynch",
        "answer": null,
        "productDetails": {
          "imtId": 11157265,
          "nmId": 14917842,
          "productName": "Coffee",
          "supplierArticle": "123401",
          "supplierName": " ГП Реклама и услуги",
          "brandName": "Nescafe"
        },
        "wasViewed": false,
        "isWarned": false
      }
    ]
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 400, 401, 402, 403, 429

---

### 1.5 Work with Questions (View / Reject / Answer / Edit)

```
PATCH /api/v1/questions
```

**Description:** Perform actions on a question — view it, reject it, answer it, or edit an existing answer. Answers can be edited within 60 days, once only.

**Request Body** (one of the following):

- **View question:**
```json
{
  "id": "n5um6IUBQOOSTxXoo0gV",
  "wasViewed": true
}
```

**Fields:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | **Yes** | Question ID |
| `wasViewed` | boolean | **Yes** | Mark as viewed |

**Response 200:**
```json
{
  "data": null,
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 400, 401, 402, 403, 404, 422, 429

---

### 1.6 Get Question by ID

```
GET /api/v1/question
```

**Description:** Returns a single question by its ID.

**Query Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `id` | string | **Yes** | Question ID |

**Response 200:**
```json
{
  "data": {
    "id": "TfWOp5QBfEYrrd0AMJau",
    "text": "Хороший карандаш? Когда еще поставите?",
    "createdDate": "2025-01-27T11:38:21.202143857Z",
    "state": "wbRu",
    "answer": {
      "text": "На следующей неделе",
      "editable": true,
      "createDate": "2025-07-28T08:24:37.187113704Z"
    },
    "productDetails": {
      "imtId": 202306781,
      "nmId": 224747484,
      "productName": "Карандаш с ластиком",
      "supplierArticle": "12113156uw",
      "supplierName": "",
      "brandName": "Brand"
    },
    "wasViewed": true,
    "isWarned": false
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 401, 402, 403, 422, 429

---

## 2. Feedbacks

### 2.1 Unanswered Feedbacks Count

```
GET /api/v1/feedbacks/count-unanswered
```

**Description:** Returns the number of unanswered feedbacks for today and for all time.

**Parameters:** None

**Response 200:**
```json
{
  "data": {
    "countUnanswered": 1,
    "countUnansweredToday": 0
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 401, 402, 403, 429

---

### 2.2 Number of Feedbacks

```
GET /api/v1/feedbacks/count
```

**Description:** Returns the number of feedbacks for the requested period.

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `dateFrom` | integer | No | — | Start date, Unix timestamp |
| `dateTo` | integer | No | — | End date, Unix timestamp |
| `isAnswered` | boolean | No | `true` | `true` = answered, `false` = not answered |

**Response 200:**
```json
{
  "data": 724583,
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 400, 401, 402, 403, 429

---

### 2.3 Feedbacks List

```
GET /api/v1/feedbacks
```

**Description:** Returns paginated feedbacks list.

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `isAnswered` | boolean | **Yes** | — | `true` = answered, `false` = not answered |
| `take` | integer | **Yes** | — | Number of feedbacks (max 5,000) |
| `skip` | integer | **Yes** | — | Number of feedbacks to skip (max 199,990) |
| `nmId` | integer | No | — | WB item number (SKU) |
| `order` | string | No | — | Sort: `dateAsc` / `dateDesc` |
| `dateFrom` | integer | No | — | Start date, Unix timestamp |
| `dateTo` | integer | No | — | End date, Unix timestamp |

**Response 200:**
```json
{
  "data": {
    "countUnanswered": 52,
    "countArchive": 1000,
    "feedbacks": [
      {
        "id": "YX52RZEBhH9mrcYdEJuD",
        "text": "Спасибо, всё подошло",
        "pros": "Удобный",
        "cons": "Нет",
        "productValuation": 5,
        "createdDate": "2024-09-26T10:20:48+03:00",
        "answer": {
          "text": "Пожалуйста. Ждём вас снова!",
          "state": "wbRu",
          "editable": false
        },
        "state": "wbRu",
        "productDetails": {
          "imtId": 123456789,
          "nmId": 987654321,
          "productName": "ВАЗ",
          "supplierArticle": "DP02/черный",
          "supplierName": "ГП Реклама и услуги",
          "brandName": "Бест Трикотаж",
          "size": "0"
        },
        "video": {
          "previewImage": "https://videofeedback01.wbbasket.ru/.../preview.webp",
          "link": "https://videofeedback01.wbbasket.ru/.../index.m3u8",
          "durationSec": 10
        },
        "wasViewed": true,
        "photoLinks": [
          { "fullSize": "https://...fs.webp", "miniSize": "https://...ms.webp" }
        ],
        "userName": "Николай",
        "orderStatus": "buyout",
        "matchingSize": "ok",
        "isAbleSupplierFeedbackValuation": false,
        "supplierFeedbackValuation": 1,
        "isAbleSupplierProductValuation": false,
        "supplierProductValuation": 2,
        "isAbleReturnProductOrders": false,
        "returnProductOrdersDate": "2024-08-20T16:39:49Z",
        "bables": ["цена"],
        "lastOrderShkId": 123456789,
        "lastOrderCreatedAt": "2024-08-12T10:20:48+03:00",
        "color": "colorless",
        "subjectId": 219,
        "subjectName": "Футболки-поло",
        "parentFeedbackId": null,
        "childFeedbackId": "bIjTCZDvJni7NGnLbUlf"
      }
    ]
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 400, 401, 402, 403, 429

---

### 2.4 Reply to Feedback

```
POST /api/v1/feedbacks/answer
```

**Description:** Sends a reply to a feedback. No validation by feedback ID — incorrect IDs will not produce an error.

**Request Body:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | **Yes** | Feedback ID |
| `text` | string | **Yes** | Reply text, 2–5000 characters |

**Request Example:**
```json
{
  "id": "J2FMRjUj6hwvwCElqssz",
  "text": "Спасибо за Ваш отзыв!"
}
```

**Response 204:** Success (no body)

**Error Codes:** 400, 401, 402, 429

---

### 2.5 Edit Response to Feedback

```
PATCH /api/v1/feedbacks/answer
```

**Description:** Edits a previously sent reply. Can be edited only once, within 60 days. No validation by feedback ID.

**Request Body:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | **Yes** | Feedback ID |
| `text` | string | **Yes** | Reply text, 2–5000 characters |

**Request Example:**
```json
{
  "id": "J2FMRjUj6hwvwCElqssz",
  "text": "Спасибо за Ваш отзыв, он очень важен для нас!"
}
```

**Response 204:** Success (no body)

**Error Codes:** 401, 402, 429

---

### 2.6 Return Item by Feedback ID

```
POST /api/v1/feedbacks/order/return
```

**Description:** Requests a return for an item associated with a feedback. Only available when `isAbleReturnProductOrders: true`.

**Request Body:**

| Field | Type | Required | Description |
|---|---|---|---|
| `feedbackId` | string | **Yes** | Feedback ID |

**Request Example:**
```json
{
  "feedbackId": "absdfgerrrfff1234"
}
```

**Response 200:**
```json
{
  "data": {},
  "error": true,
  "errorText": "string",
  "additionalErrors": ["string"]
}
```

**Error Codes:** 400, 401, 402, 422, 429

---

### 2.7 Get Feedback by ID

```
GET /api/v1/feedback
```

**Description:** Returns a single feedback by its ID.

**Query Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `id` | string | **Yes** | Feedback ID |

**Response 200:**
```json
{
  "data": {
    "id": "YX52RZEBhH9mrcYdEJuD",
    "text": "Спасибо, всё подошло",
    "pros": "Удобный",
    "cons": "Нет",
    "productValuation": 5,
    "createdDate": "2024-09-26T10:20:48+03:00",
    "answer": {
      "text": "Пожалуйста. Ждём вас снова!",
      "state": "wbRu",
      "editable": false
    },
    "state": "wbRu",
    "productDetails": {
      "imtId": 123456789,
      "nmId": 987654321,
      "productName": "ВАЗ",
      "supplierArticle": "DP02/черный",
      "supplierName": "ГП Реклама и услуги",
      "brandName": "Бест Трикотаж",
      "size": "0"
    },
    "video": {
      "previewImage": "https://videofeedback01.wbbasket.ru/.../preview.webp",
      "link": "https://videofeedback01.wbbasket.ru/.../index.m3u8",
      "durationSec": 10
    },
    "wasViewed": true,
    "photoLinks": [
      { "fullSize": "https://...fs.webp", "miniSize": "https://...ms.webp" }
    ],
    "userName": "Николай",
    "orderStatus": "returned",
    "matchingSize": "ok",
    "isAbleSupplierFeedbackValuation": false,
    "supplierFeedbackValuation": 1,
    "isAbleSupplierProductValuation": false,
    "supplierProductValuation": 2,
    "isAbleReturnProductOrders": false,
    "returnProductOrdersDate": "2024-08-20T16:39:49Z",
    "bables": ["цена"],
    "lastOrderShkId": 123456789,
    "lastOrderCreatedAt": "2024-08-12T10:20:48+03:00",
    "color": "colorless",
    "subjectId": 219,
    "subjectName": "Футболки-поло",
    "parentFeedbackId": null,
    "childFeedbackId": "bIjTCZDvJni7NGnLbUlf"
  },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

**Error Codes:** 401, 402, 422, 429

---

### 2.8 List of Archived Feedbacks

```
GET /api/v1/feedbacks/archive
```

**Description:** Returns archived feedbacks. A feedback becomes archived when:
- A response is received
- No response within 30 days
- Contains no text or photos

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `take` | integer | **Yes** | — | Number of feedbacks (max 5,000) |
| `skip` | integer | **Yes** | — | Number of feedbacks to skip |
| `nmId` | integer | No | — | WB item number (SKU) |
| `order` | string | No | — | Sort: `dateAsc` / `dateDesc` |

**Response 200:** (Same structure as Feedbacks List)

**Error Codes:** 400, 401, 402, 403, 422, 429

---

## 3. Pinned Feedback

> Requires **Jam subscription** or **Pin a feedback** tariff option for pinning.

### 3.1 List of Pinned / Unpinned Feedback

```
GET /api/feedbacks/v1/pins
```

**Description:** Returns pinned and unpinned feedback list. Unpinned items include the unpin reason in `unpinnedCause`.

**Query Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `state` | string | No | `pinned` / `unpinned` |
| `pinOn` | string | No | `nm` (listing) / `imt` (merged listing group) |
| `imtId` | integer | No | Merged listing ID |
| `nmId` | integer | No | WB item number |
| `feedbackId` | integer | No | Feedback ID |
| `dateFrom` | string (date-time) | No | Pin date range start |
| `dateTo` | string (date-time) | No | Pin date range end |
| `next` | integer | No | Paginator — last pinning operation ID |
| `limit` | integer | No (default 500) | Items per page, max 500 |

**Response 200:**
```json
{
  "data": [
    {
      "changeStateAt": "2020-01-01T15:04:05Z",
      "imtId": 256971531,
      "nmId": 177974151,
      "pinId": 1857762,
      "pinMethod": "subscription",
      "pinOn": "imt",
      "feedbackId": "DibuRAImknLyiqgzvGcU",
      "state": "unpinned",
      "unpinnedCause": "sysTariffUnpinned"
    }
  ],
  "next": 200
}
```

**Error Codes:** 400, 401, 402, 429

---

### 3.2 Pin Feedback

```
POST /api/feedbacks/v1/pins
```

**Description:** Pins feedback to a listing or merged listing group. Requires Jam subscription or tariff option.

**Request Body** (JSON array, max 500 items):

| Field | Type | Required | Description |
|---|---|---|---|
| `pinMethod` | string | **Yes** | `subscription` or `tariff` |
| `pinOn` | string | **Yes** | `nm` (listing) or `imt` (merged listing group) |
| `feedbackId` | string | **Yes** | Feedback ID |

**Request Example:**
```json
[
  { "pinMethod": "subscription", "pinOn": "imt", "feedbackId": "VlbkVVl7mtw37wуWkJZz" },
  { "pinMethod": "tariff", "pinOn": "imt", "feedbackId": "DibuRAImknLyiqgzvGcU" }
]
```

**Response 200:**
```json
{
  "data": [
    {
      "feedbackId": "VlbkVVl7mtw37wуWkJZz",
      "pinId": 18577062,
      "pinMethod": "subscription",
      "pinOn": "imt",
      "isErrors": false
    },
    {
      "feedbackId": "DibuRAImknLyiqgzvGcU",
      "pinMethod": "tariff",
      "pinOn": "imt",
      "isErrors": true,
      "errors": [
        {
          "status": "itemNotFound",
          "title": "item not found",
          "detail": "item not found or does not belong to seller",
          "requestId": "0414dc48df701618e0a3bfc414fe3136",
          "origin": "pin-open-api"
        }
      ]
    }
  ]
}
```

**Error Codes:** 400, 401, 402, 403, 429

---

### 3.3 Unpin Feedback

```
DELETE /api/feedbacks/v1/pins
```

**Description:** Unpins feedback. Use `pinId` from the list endpoint.

**Request Body** (JSON array of integers, max 500 items):

```json
[123456, 234567, 345678]
```

**Response 200:**
```json
{
  "data": [123456, 234567, 345678]
}
```

**Error Codes:** 400, 401, 402, 429

---

### 3.4 Pinned / Unpinned Feedback Count

```
GET /api/feedbacks/v1/pins/count
```

**Description:** Returns pinned and unpinned feedback count for a period.

**Query Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `state` | string | No | `pinned` / `unpinned` |
| `pinOn` | string | No | `nm` / `imt` |
| `imtId` | integer | No | Merged listing ID |
| `nmId` | integer | No | WB item number |
| `feedbackId` | integer | No | Feedback ID |
| `dateFrom` | string (date-time) | No | Pin date range start |
| `dateTo` | string (date-time) | No | Pin date range end |

**Response 200:**
```json
{
  "data": 0
}
```

**Error Codes:** 400, 401, 402, 429

---

### 3.5 Pinned Feedback Limits

```
GET /api/feedbacks/v1/pins/limits
```

**Description:** Returns pinned feedback limits for tariff and subscription.

**Parameters:** None

**Response 200:**
```json
{
  "data": {
    "subscription": {
      "perUnitLimit": 2,
      "remaining": 5,
      "totalLimit": 15,
      "unlimited": false,
      "used": 10
    },
    "tariff": {
      "perUnitLimit": 2,
      "remaining": 5,
      "totalLimit": 15,
      "unlimited": false,
      "used": 10
    }
  }
}
```

**Error Codes:** 401, 402, 429

---

## 4. Buyers Chat

> Communication between sellers and buyers. Buyer always starts the chat. Respond within 10 days recommended.
> Return processing is only available via the [web version](https://seller.wildberries.ru/chat-with-clients).

### Rate Limits

| Type | Period | Limit | Interval | Burst |
|---|---|---|---|---|
| Personal | 10s | 10 req | 1s | 10 req |
| Service | 10s | 10 req | 1s | 10 req |
| Base with secret | 10s | 10 req | 1s | 10 req |
| Base | 1h | 1 req | 1h | 1 req |

---

### 4.1 Chats List

```
GET /api/v1/seller/chats
```

**Description:** Returns all seller chats.

**Parameters:** None

**Response 200:**
```json
{
  "result": [
    {
      "chatID": "1:4019cd7d-cca8-4e90-8b11-f78afbea42e3",
      "replySign": "1:4019cd7d-...:...",
      "clientName": "Иван",
      "goodCard": {
        "date": "string",
        "nmID": 0,
        "price": 0,
        "priceCurrency": "string",
        "rid": "string",
        "size": "string"
      },
      "lastMessage": {
        "text": "Можно заказать 100 штук?",
        "addTimestamp": 1766138234889
      }
    }
  ],
  "errors": null
}
```

**Error Codes:** 401, 402, 429

---

### 4.2 Chat Events

```
GET /api/v1/seller/events
```

**Description:** Returns events for all chats. Uses cursor-based pagination via `next`.

**Polling strategy:**
1. First request without `next`
2. Repeat with `next` from previous response until `totalEvents` becomes `0`

**Query Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `next` | integer | No | Paginator — Unix timestamp **with milliseconds** |

**Response 200:**
```json
{
  "result": {
    "next": 1698045576000,
    "newestEventTime": "2023-10-23T07:19:36Z",
    "oldestEventTime": "2023-10-23T05:02:20Z",
    "totalEvents": 4,
    "events": [
      {
        "chatID": "1:1e265a58-a120-b178-008c-60af2460207c",
        "eventID": "55adee45-11f0-33b6-a847-6ccc7c78b2ec",
        "eventType": "message",
        "isNewChat": true,
        "message": {
          "attachments": {
            "goodCard": {
              "date": "2023-10-18T11:46:01.528526Z",
              "nmID": 12345678,
              "price": 500,
              "priceCurrency": "RUB",
              "rid": "2fb52cd9e25e52538a5f05994e688ae5",
              "size": "0"
            },
            "files": [
              {
                "contentType": "application/pdf",
                "date": "2023-10-23T08:02:19.594Z",
                "downloadID": "ecaeb056-a4ee-45b4-ae45-666811755d38",
                "name": "Чек.pdf",
                "url": "https://chat-basket-01.wbbasket.ru/.../file.pdf",
                "size": 1046143
              }
            ],
            "images": [
              {
                "date": "2023-10-23T08:02:20.717Z",
                "downloadID": "fd6be4e3-5447-41d7-a1e6-b2d3e06c3b05",
                "url": "https://chat-basket-01.wbbasket.ru/.../image.jpg"
              }
            ]
          },
          "text": "Здравствуйте! У меня вопрос по товару..."
        },
        "source": "rusite",
        "addTimestamp": 1698037340000,
        "addTime": "2023-10-23T05:02:20Z",
        "replySign": "1:1e265a58-a120-b178-008c-60af2460207c:...",
        "sender": "client",
        "clientName": "Алёна"
      }
    ]
  },
  "errors": null
}
```

**Error Codes:** 400, 401, 402, 429

---

### 4.3 Send Message

```
POST /api/v1/seller/message
```

**Description:** Sends a message to the buyer.

**Request Body** (`multipart/form-data`):

| Field | Type | Required | Description |
|---|---|---|---|
| `replySign` | string | **Yes** | Chat signature from chat info or new-chat event, max 255 chars |
| `message` | string | No | Message text, max 1000 characters |
| `file` | file[] | No | Files (JPEG/PDF/PNG), max 5 MB each, max 30 MB total |

**Response 200:**
```json
{
  "result": {
    "addTime": 1712848270018,
    "chatID": "1:641b623c-5c0e-295b-db03-3d5b4d484c32"
  },
  "errors": []
}
```

**Error Codes:** 400, 401, 402, 429

---

### 4.4 Get File from Message

```
GET /api/v1/seller/download/{id}
```

**Description:** Downloads a file or image from a message by its `downloadID`.

**Path Parameters:**

| Parameter | Type | Required | Description |
|---|---|---|---|
| `id` | string | **Yes** | File ID from `downloadID` field in chat events |

**Response 200:** Binary file content

**Response 202** (moderation pending):
```json
{
  "moderationState": "pending",
  "retrySeconds": 30
}
```

**Error Codes:** 400, 401, 402, 429, 451 (moderation failed)

---

## 5. Buyers Returns

### Rate Limits

| Type | Period | Limit | Interval | Burst |
|---|---|---|---|---|
| Personal | 1 min | 20 req | 3s | 10 req |
| Service | 1 min | 20 req | 3s | 10 req |
| Base with secret | 1 min | 20 req | 3s | 10 req |
| Base | 1h | 1 req | 1h | 1 req |

---

### 5.1 Buyers Return Applications

```
GET /api/v1/claims
```

**Description:** Returns buyer return applications for the last 14 days.

**Query Parameters:**

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `is_archive` | boolean | **Yes** | — | `false` = under review, `true` = in archive |
| `id` | string (UUID) | No | — | Application ID |
| `limit` | integer | No | 50 | Items per page (1–200) |
| `offset` | integer | No | 0 | Starting offset |
| `nm_id` | integer | No | — | WB item number (SKU) |

**Response 200:**
```json
{
  "claims": [
    {
      "id": "fe3e9337-e9f9-423c-8930-946a8ebef80",
      "claim_type": 1,
      "status": 2,
      "status_ex": 8,
      "nm_id": 196320101,
      "user_comment": "Длина провода не соответствует описанию",
      "wb_comment": "Продавец одобрил вашу заявку...",
      "dt": "2025-03-26T17:06:12.245611",
      "imt_name": "Кабель 0.5 м, 3797",
      "order_dt": "2024-10-27T05:18:56",
      "dt_update": "2025-05-10T18:01:06.999613",
      "photos": [
        "//photos.wbstatic.net/claim/fe3e9337-.../1.webp",
        "//photos.wbstatic.net/claim/fe3e9337-.../2.webp"
      ],
      "video_paths": [
        "//video.wbstatic.net/claim/fe3e9337-.../1.mp4"
      ],
      "actions": ["autorefund1", "approve1"],
      "price": 157,
      "currency_code": "643",
      "srid": "v5o_7143225816503318733.0.0",
      "origin_id_info": "IMEI 359889346153011...",
      "delivery_dt": "2025-04-09T14:36:07"
    }
  ],
  "total": 31
}
```

**Error Codes:** 400, 401, 402, 429

---

### 5.2 Answer Buyers Application

```
PATCH /api/v1/claim
```

**Description:** Sends an answer to a buyer's return application.

**Request Body:**

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string (UUID) | **Yes** | Application ID |
| `action` | string | **Yes** | Use one of the `actions` array values from the claims response |
| `comment` | string | No* | 10–1000 characters. *Required when `action` is `rejectcustom` or `approvecc1` |

**Request Example:**
```json
{
  "id": "fe3e9337-e9f9-423c-8930-946a8ebef80",
  "action": "rejectcustom",
  "comment": "The photo is not related to the item in the application"
}
```

**Response 200:** Success

**Error Codes:** 400, 401, 402, 429

---

## Common Error Codes

| Code | Description |
|---|---|
| 200 | Success |
| 202 | File under moderation (Chat) |
| 204 | Success, no body |
| 400 | Bad request |
| 401 | Unauthorized |
| 402 | Payment required |
| 403 | Access denied |
| 404 | Not found |
| 422 | Validation / processing error |
| 429 | Rate limit exceeded |
| 451 | Moderation failed (Chat) |

---

## Common Response Envelope

Most Feedbacks & Questions endpoints use this envelope:

```json
{
  "data": { ... },
  "error": false,
  "errorText": "",
  "additionalErrors": null
}
```

Chat and Returns endpoints use:

```json
{
  "result": { ... },
  "errors": null
}
```
