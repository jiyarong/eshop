# 客户沟通 API（聊天、评价、问答）

**Base URL**: `//api-seller.ozon.ru`  
**版本**: 2.1  

More methods in the [**Premium Methods**](#tag/Premium) section.

---

## 接口列表

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/chat/send/file` | Send file |
| POST | `/v2/chat/list` | Chats list |
| POST | `/v3/chat/list` | Chats list |
| POST | `/v3/chat/history` | Chat history |
| POST | `/v1/review/comment/create` | Leave a comment on the review |
| POST | `/v1/review/comment/delete` | Delete a comment on a review |
| POST | `/v1/review/comment/list` | List of comments for the review |
| POST | `/v1/review/change-status` | Change review status |
| POST | `/v1/review/count` | Number of reviews by status |
| POST | `/v1/review/info` | Get review details |
| POST | `/v1/review/list` | Get a list of reviews |
| POST | `/v1/question/answer/create` | Create answer to question |
| POST | `/v1/question/answer/delete` | Delete answer to question |
| POST | `/v1/question/answer/list` | List of answers to question |
| POST | `/v1/question/change-status` | Change question statuses |
| POST | `/v1/question/count` | Number of questions by statuses |
| POST | `/v1/question/info` | Question details |
| POST | `/v1/question/list` | Question list |
| POST | `/v1/question/top-sku` | Products with the most questions |

---

## 接口详情


### POST `/v1/chat/send/file`
**Send file**  
operationId: `ChatAPI_ChatSendFile`  

Sends a file to an existing chat by its identifier.

Only sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions) or Premium Pro subscription can send files to chats with customers.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `base64_content` | string | ✓ | File as a base64 string. |
| `chat_id` | string | ✓ | Chat identifier. |
| `name` | string | ✓ | File name with extension. |

**响应 200**: File is sent
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `result` | string |  | Method result. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v2/chat/list`
**Chats list**  
operationId: `ChatAPI_ChatListV2`  

Returns information about chats by specified filters. <aside class="warning"> This method will be disabled. Switch to the <a href="#operation/ChatAPI_ChatListV3">/v3/chat/list</a> method. </aside>

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `ChatListRequestFilter` |  |  |
| `limit` | integer | ✓ | Number of values in the response. The default value is 30. The maximum value is 100. |
| `cursor` | string |  | Cursor for the next data sample. |

**响应 200**: Chats list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `chats` | any |  | Chats data. |
| `total_chats_count` | integer |  | Total number of chats. |
| `total_unread_count` | integer |  | Total number of unread messages. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v3/chat/list`
**Chats list**  
operationId: `ChatAPI_ChatListV3`  

Returns information about chats by specified filters.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `ChatListRequestFilter` |  |  |
| `limit` | integer | ✓ | Number of values in the response. The default value is 30. The maximum value is 100. |
| `cursor` | string |  | Cursor for the next data sample. |

**响应 200**: Chats list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `chats` | any |  | Chats data. |
| `total_unread_count` | integer |  | Total number of unread messages. |
| `cursor` | string |  | Cursor for the next data sample. |
| `has_next` | boolean |  | Indicates that the response does not contain all chats:   - `true`: send another request with a new  |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |
**响应 403**: Access denied
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v3/chat/history`
**Chat history**  
operationId: `ChatAPI_ChatHistoryV3`  

Returns the history of chat messages. By default messages are shown from newest to oldest.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `chat_id` | string | ✓ | Chat identifier. |
| `direction` | string |  | Direction of message sorting: - `Forward`: from old to new. - `Backward`: from new to old.  The defa |
| `filter` | `ChatHistoryRequestFilter` |  |  |
| `from_message_id` | integer |  | Identifier of the message from which the chat history is displayed. Default value is the last visibl |
| `limit` | integer |  | Number of messages in the response. The default value is 50. The maximum value is 1000. |

**响应 200**: Chat history
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | `true`, if not all messages were returned in the response.  |
| `messages` | array[v3ChatMessage] |  | Array of messages sorted according to the `direction` parameter in the request body. |
**响应 400**: Invalid parameter
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/comment/create`
**Leave a comment on the review**  
operationId: `ReviewAPI_CommentCreate`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `mark_review_as_processed` | boolean |  | Review status update: - `true`: status changes to `Processed`. - `false`: status doesn't change.  |
| `parent_comment_id` | string |  | Identifier of the parent comment you're replying to. |
| `review_id` | string | ✓ | Review identifier. |
| `text` | string | ✓ | Comment text. |

**响应 200**: Comment created
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `comment_id` | string |  | Comment identifier. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/comment/delete`
**Delete a comment on a review**  
operationId: `ReviewAPI_CommentDelete`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `comment_id` | string | ✓ | Comment identifier. |

**响应 200**: Comment deleted
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/comment/list`
**List of comments for the review**  
operationId: `ReviewAPI_CommentList`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

Method returns information about comments on reviews that have passed moderation.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer | ✓ | Limit of values in the response. Minimum is 20. Maximum is 100.  |
| `offset` | integer |  | Number of elements that is skipped in the response. For example, if `offset = 10`, the response star |
| `review_id` | string | ✓ | Review identifier. |
| `sort_dir` | `v1CommentSort` |  |  |

**响应 200**: Details about comments on the review
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `comments` | array[CommentListResponseComment] |  | Comment details. |
| `offset` | integer |  | Number of elements in the response. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/change-status`
**Change review status**  
operationId: `ReviewAPI_ReviewChangeStatus`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `review_ids` | array[string] | ✓ | Array with review identifiers from 1 to 100. |
| `status` | string | ✓ | Review status: - `PROCESSED`: processed, - `UNPROCESSED`: not processed.  |

**响应 200**: Status changed
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/count`
**Number of reviews by status**  
operationId: `ReviewAPI_ReviewCount`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

**响应 200**: Number of processed and unprocessed reviews
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `processed` | integer |  | Number of processed reviews. |
| `total` | integer |  | Number of all reviews. |
| `unprocessed` | integer |  | Number of unprocessed reviews. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/info`
**Get review details**  
operationId: `ReviewAPI_ReviewInfo`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `review_id` | string | ✓ | Review identifier. |

**响应 200**: Review details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `comments_amount` | integer |  | Number of comments on the review. |
| `dislikes_amount` | integer |  | Number of dislikes on the review. |
| `id` | string |  | Review identifier. |
| `is_rating_participant` | boolean |  | `true`, if the review affects the rating calculation.  |
| `likes_amount` | integer |  | Number of likes on the review. |
| `order_status` | string |  | Status of the order for which the customer left a review: - `DELIVERED`: delivered, - `CANCELLED`: c |
| `photos` | array[ReviewInfoResponsePhoto] |  | Image details. |
| `photos_amount` | integer |  | Number of images in the review. |
| `published_at` | string |  | Review publication date. |
| `rating` | integer |  | Review rating. |
| `sku` | integer |  | Product identifier in the Ozon system, SKU. |
| `status` | string |  | Review status: - `UNPROCESSED`: not processed, - `PROCESSED`: processed.  |
| `text` | string |  | Review text. |
| `videos` | array[ReviewInfoResponseVideo] |  | Video details. |
| `videos_amount` | integer |  | Number of videos for the review. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/review/list`
**Get a list of reviews**  
operationId: `ReviewAPI_ReviewList`  

Available to sellers with the [Review Management](https://docs.ozon.ru/global/en/work-with-customers/managing-reviews/managing-reviews-subscription/) or Premium Pro subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1089-Metody-sozdaniia-zaiavok-na-postavku)
in the Ozon for dev community.

Method doesn't return the “Advantages” and “Disadvantages” parameters if they are included in product reviews. The parameters are outdated and aren't included in new reviews.

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | string |  | Identifier of the last review on the page. |
| `limit` | integer | ✓ | Number of reviews in the response. Minimum is 20, maximum is 100. |
| `sort_dir` | string |  | Sorting direction: - `ASC`: ascending, - `DESC`: descending.  |
| `status` | string |  | Review statuses: - `ALL`: all statuses, - `UNPROCESSED`: not processed, - `PROCESSED`: processed.  |

**响应 200**: List of reviews
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `has_next` | boolean |  | `true`, if not all reviews were returned in the response.  |
| `last_id` | string |  | Identifier of the last review on the page. |
| `reviews` | array[ReviewListResponseReview] |  | Review details. |
**响应 default**: Errors
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | array[protobufAny] |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/answer/create`
**Create answer to question**  
operationId: `QuestionAnswer_Create`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `question_id` | string | ✓ | Question identifier. |
| `sku` | integer | ✓ | Product SKU in Ozon system. |
| `text` | string | ✓ | Answer text from 2 to 3,000 characters long. |

**响应 200**: Identifier of answer to question
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `answer_id` | string |  | Identifier of answer to question. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/answer/delete`
**Delete answer to question**  
operationId: `QuestionAnswer_Delete`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `answer_id` | string | ✓ | Answer identifier. |
| `sku` | integer | ✓ | Product SKU in Ozon system. |

**响应 200**: Answer deleted
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/answer/list`
**List of answers to question**  
operationId: `QuestionAnswer_List`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `last_id` | None |  | Identifier of the last value on the page.  Leave blank for the first request. For the next values, s |
| `question_id` | string | ✓ | Question identifier. |
| `sku` | integer | ✓ | Product SKU in Ozon system. |

**响应 200**: List of answers to question
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `answers` | any |  | Answers. |
| `last_id` | string |  | Identifier of the last value on the page.  To get the next values, specify the received value in the |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/change-status`
**Change question statuses**  
operationId: `Question_ChangeStatus`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `question_ids` | any | ✓ | Question identifiers. |
| `status` | string | ✓ | Question statuses: - `NEW`, - `VIEWED`, - `PROCESSED`.  |

**响应 200**: Status changed
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/count`
**Number of questions by statuses**  
operationId: `Question_Count`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**响应 200**: Number of questions by statuses
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `all` | integer |  | Total number of questions. |
| `new` | integer |  | New questions. |
| `processed` | integer |  | Processed questions. |
| `unprocessed` | integer |  | Unprocessed questions. |
| `viewed` | integer |  | Viewed questions. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/info`
**Question details**  
operationId: `Question_Info`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `question_id` | string | ✓ | Question identifier. |

**响应 200**: Question details
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `answers_count` | integer |  | Number of answers to question. |
| `author_name` | string |  | Question author. |
| `id` | string |  | Question identifier. |
| `product_url` | string |  | Product link. |
| `published_at` | timestamp |  | Question publication date. |
| `question_link` | string |  | Question link. |
| `sku` | integer |  | Product SKU in Ozon system. |
| `status` | enum |  | Question status: - `NEW`, - `ALL`: all questions, - `VIEWED`, - `PROCESSED`, - `UNPROCESSED`.  |
| `text` | string |  | Question text. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/list`
**Question list**  
operationId: `Question_List`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `filter` | `v1QuestionListRequestFilter` |  |  |
| `last_id` | string |  | Identifier of the last value on the page.   Leave blank for the first request. For the next values,  |

**响应 200**: Question list
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `questions` | any |  | Questions. |
| `last_id` | string |  | Identifier of the last value on the page.  To get the next values, specify the received value in the |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---

### POST `/v1/question/top-sku`
**Products with the most questions**  
operationId: `Question_TopSku`  

Available to sellers with the [Premium Plus](https://docs.ozon.ru/global/en/promotion/subscriptions/premium-plus/) subscription.

You can leave feedback on this method in the comments section to the [discussion](https://dev.ozon.ru/community/1198-Metody-dlia-raboty-s-voprosami-otvetami) in the Ozon for dev community.

**参数**:

| 名称 | 位置 | 类型 | 必填 | 说明 |
|------|------|------|------|------|
| `Client-Id` | header | string | ✓ | Client ID. |
| `Api-Key` | header | string | ✓ | API key. |

**请求体** (`application/json`):

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `limit` | integer | ✓ | Number of values in the response.  |

**响应 200**: Products with the most questions
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `sku` | any |  | List of product SKUs in Ozon system. |
**响应 default**: Error
| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer |  | Error code. |
| `details` | string |  | Error details. |
| `message` | string |  | Error description. |

---