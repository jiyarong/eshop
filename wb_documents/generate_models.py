"""Generate all raw_wb_ model files for Rails."""
import os

BASE = "/Users/jiyarong/Developer/5/ecommerce_manage/app/models"

MODELS = {
    # name: (table, belongs_to list, has_many list)
    "raw_wb/platform": (
        "raw_wb_platforms",
        [],
        ["raw_wb/seller_account"]
    ),
    "raw_wb/seller_account": (
        "raw_wb_seller_accounts",
        [("raw_wb/platform", "platform")],
        ["raw_wb/product", "raw_wb/warehouse", "raw_wb/order", "raw_wb/supply",
         "raw_wb/ad_campaign", "raw_wb/promotion", "raw_wb/review",
         "raw_wb/question", "raw_wb/chat", "raw_wb/return_claim",
         "raw_wb/account_balance", "raw_wb/sales_report", "raw_wb/sync_task"]
    ),
    "raw_wb/category": (
        "raw_wb_categories",
        [],
        ["raw_wb/subject"]
    ),
    "raw_wb/subject": (
        "raw_wb_subjects",
        [("raw_wb/category", "category")],
        ["raw_wb/characteristic", "raw_wb/product"]
    ),
    "raw_wb/characteristic": (
        "raw_wb_characteristics",
        [("raw_wb/subject", "subject")],
        []
    ),
    "raw_wb/attribute_dict": (
        "raw_wb_attribute_dicts",
        [],
        []
    ),
    "raw_wb/product": (
        "raw_wb_products",
        [("raw_wb/seller_account", "account"), ("raw_wb/subject", "subject")],
        ["raw_wb/product_characteristic", "raw_wb/product_sku",
         "raw_wb/product_medium", "raw_wb/product_tag_link",
         "raw_wb/product_price", "raw_wb/product_price_history"]
    ),
    "raw_wb/product_characteristic": (
        "raw_wb_product_characteristics",
        [("raw_wb/product", "product")],
        []
    ),
    "raw_wb/product_sku": (
        "raw_wb_product_skus",
        [("raw_wb/product", "product")],
        ["raw_wb/stock"]
    ),
    "raw_wb/product_medium": (
        "raw_wb_product_media",
        [("raw_wb/product", "product")],
        []
    ),
    "raw_wb/product_tag": (
        "raw_wb_product_tags",
        [("raw_wb/seller_account", "account")],
        ["raw_wb/product_tag_link"]
    ),
    "raw_wb/product_tag_link": (
        "raw_wb_product_tag_links",
        [("raw_wb/product", "product"), ("raw_wb/product_tag", "tag")],
        []
    ),
    "raw_wb/product_price": (
        "raw_wb_product_prices",
        [("raw_wb/product", "product"), ("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/product_price_history": (
        "raw_wb_product_price_histories",
        [("raw_wb/product", "product")],
        []
    ),
    "raw_wb/warehouse": (
        "raw_wb_warehouses",
        [("raw_wb/seller_account", "account")],
        ["raw_wb/stock", "raw_wb/order"]
    ),
    "raw_wb/stock": (
        "raw_wb_stocks",
        [("raw_wb/seller_account", "account"),
         ("raw_wb/warehouse", "warehouse"),
         ("raw_wb/product_sku", "sku")],
        []
    ),
    "raw_wb/stock_history": (
        "raw_wb_stock_histories",
        [("raw_wb/warehouse", "warehouse")],
        []
    ),
    "raw_wb/order": (
        "raw_wb_orders",
        [("raw_wb/seller_account", "account"), ("raw_wb/warehouse", "warehouse")],
        ["raw_wb/order_meta", "raw_wb/order_status_history",
         "raw_wb/supply_order", "raw_wb/chat", "raw_wb/return_claim"]
    ),
    "raw_wb/order_meta": (
        "raw_wb_order_metas",
        [("raw_wb/order", "order")],
        []
    ),
    "raw_wb/order_status_history": (
        "raw_wb_order_status_histories",
        [("raw_wb/order", "order")],
        []
    ),
    "raw_wb/supply": (
        "raw_wb_supplies",
        [("raw_wb/seller_account", "account")],
        ["raw_wb/supply_order", "raw_wb/supply_box"]
    ),
    "raw_wb/supply_order": (
        "raw_wb_supply_orders",
        [("raw_wb/supply", "supply"), ("raw_wb/order", "order")],
        []
    ),
    "raw_wb/supply_box": (
        "raw_wb_supply_boxes",
        [("raw_wb/supply", "supply")],
        []
    ),
    "raw_wb/ad_campaign": (
        "raw_wb_ad_campaigns",
        [("raw_wb/seller_account", "account")],
        ["raw_wb/ad_campaign_product", "raw_wb/ad_keyword_bid",
         "raw_wb/ad_negative_keyword", "raw_wb/ad_daily_stat"]
    ),
    "raw_wb/ad_campaign_product": (
        "raw_wb_ad_campaign_products",
        [("raw_wb/ad_campaign", "campaign")],
        []
    ),
    "raw_wb/ad_keyword_bid": (
        "raw_wb_ad_keyword_bids",
        [("raw_wb/ad_campaign", "campaign")],
        []
    ),
    "raw_wb/ad_negative_keyword": (
        "raw_wb_ad_negative_keywords",
        [("raw_wb/ad_campaign", "campaign")],
        []
    ),
    "raw_wb/ad_daily_stat": (
        "raw_wb_ad_daily_stats",
        [("raw_wb/ad_campaign", "campaign")],
        []
    ),
    "raw_wb/promotion": (
        "raw_wb_promotions",
        [("raw_wb/seller_account", "account")],
        ["raw_wb/promotion_product"]
    ),
    "raw_wb/promotion_product": (
        "raw_wb_promotion_products",
        [("raw_wb/promotion", "promotion")],
        []
    ),
    "raw_wb/analytics_sales_funnel": (
        "raw_wb_analytics_sales_funnels",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/analytics_search_term": (
        "raw_wb_analytics_search_terms",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/review": (
        "raw_wb_reviews",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/question": (
        "raw_wb_questions",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/chat": (
        "raw_wb_chats",
        [("raw_wb/seller_account", "account"), ("raw_wb/order", "order")],
        ["raw_wb/chat_message"]
    ),
    "raw_wb/chat_message": (
        "raw_wb_chat_messages",
        [("raw_wb/chat", "chat")],
        []
    ),
    "raw_wb/return_claim": (
        "raw_wb_return_claims",
        [("raw_wb/seller_account", "account"), ("raw_wb/order", "order")],
        []
    ),
    "raw_wb/account_balance": (
        "raw_wb_account_balances",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/sales_report": (
        "raw_wb_sales_reports",
        [("raw_wb/seller_account", "account")],
        ["raw_wb/sales_report_item"]
    ),
    "raw_wb/sales_report_item": (
        "raw_wb_sales_report_items",
        [("raw_wb/sales_report", "sales_report"),
         ("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/stats_order": (
        "raw_wb_stats_orders",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/stats_sale": (
        "raw_wb_stats_sales",
        [("raw_wb/seller_account", "account")],
        []
    ),
    "raw_wb/sync_task": (
        "raw_wb_sync_tasks",
        [("raw_wb/seller_account", "account")],
        []
    ),
}


def class_name(path):
    parts = path.split("/")
    return "::".join(p.split("_")[-1] if i == 0 and p == "raw_wb" else
                     "".join(w.capitalize() for w in p.split("_"))
                     for i, p in enumerate(parts))


def model_class_name(path):
    parts = path.split("/")
    result = []
    for p in parts:
        result.append("".join(w.capitalize() for w in p.split("_")))
    return "::".join(result)


for model_path, (table, belongs_tos, has_manys) in MODELS.items():
    parts = model_path.split("/")
    namespace = parts[0]  # raw_wb
    name = parts[1]

    dir_path = os.path.join(BASE, namespace)
    os.makedirs(dir_path, exist_ok=True)

    class_parts = [
        "".join(w.capitalize() for w in p.split("_")) for p in parts
    ]
    class_full = "::".join(class_parts)

    lines = []
    lines.append(f"module {class_parts[0]}")
    lines.append(f"  class {class_parts[1]} < ApplicationRecord")
    lines.append(f"    self.table_name = '{table}'")
    lines.append("")

    for bt_path, bt_name in belongs_tos:
        bt_parts = bt_path.split("/")
        bt_class = "::".join("".join(w.capitalize() for w in p.split("_")) for p in bt_parts)
        lines.append(f"    belongs_to :{bt_name}, class_name: '{bt_class}'")

    if belongs_tos and has_manys:
        lines.append("")

    for hm_path in has_manys:
        hm_parts = hm_path.split("/")
        hm_class = "::".join("".join(w.capitalize() for w in p.split("_")) for p in hm_parts)
        hm_name = hm_parts[-1]
        lines.append(f"    has_many :{hm_name}s, class_name: '{hm_class}', foreign_key: :{'account_id' if 'account' in [b[1] for b in belongs_tos] and hm_path.split('/')[-1] != 'chat_message' and hm_path.split('/')[-1] != 'supply_order' and hm_path.split('/')[-1] != 'supply_box' and hm_path.split('/')[-1] != 'order_meta' and hm_path.split('/')[-1] != 'order_status_history' else name + '_id'}")

    lines.append("  end")
    lines.append("end")
    lines.append("")

    file_path = os.path.join(dir_path, f"{name}.rb")
    with open(file_path, "w") as f:
        f.write("\n".join(lines))

print(f"Generated {len(MODELS)} model files")
