"""Generate controllers and jbuilder views for all raw_wb resources."""
import os

ROOT = "/Users/jiyarong/Developer/5/ecommerce_manage"
CTL_DIR = f"{ROOT}/app/controllers/raw_wb"
VIEW_DIR = f"{ROOT}/app/views/raw_wb"

# (snake_name, ModelClass, index_fields, show_fields)
RESOURCES = [
    ("platforms",                "Platform",              ["id","code","name","base_api_url","created_at"],                        ["id","code","name","base_api_url","created_at","updated_at"]),
    ("seller_accounts",          "SellerAccount",         ["id","name","token_type","is_active","created_at"],                     ["id","platform_id","name","token_type","token_expires_at","is_active","created_at","updated_at"]),
    ("categories",               "Category",              ["id","wb_id","name","name_en","synced_at"],                             ["id","wb_id","name","name_en","name_zh","synced_at"]),
    ("subjects",                 "Subject",               ["id","wb_id","name","category_id","synced_at"],                        ["id","wb_id","name","name_en","category_id","synced_at"]),
    ("products",                 "Product",               ["id","nm_id","vendor_code","brand","title","subject_name","is_in_trash","synced_at"], ["id","nm_id","imt_id","vendor_code","brand","title","description","subject_id","subject_name","wb_category","is_in_trash","created_at","updated_at","synced_at"]),
    ("product_skus",             "ProductSku",            ["id","product_id","chrt_id","tech_size","wb_size","barcode"],           ["id","product_id","chrt_id","tech_size","wb_size","barcode","created_at"]),
    ("product_prices",           "ProductPrice",          ["id","product_id","price","discount","club_discount","final_price","is_in_quarantine"], ["id","product_id","account_id","price","discount","club_discount","final_price","is_in_quarantine","updated_at"]),
    ("warehouses",               "Warehouse",             ["id","wb_warehouse_id","name","city","warehouse_type","is_active"],     ["id","wb_warehouse_id","name","address","work_time","city","longitude","latitude","warehouse_type","is_active","created_at","updated_at"]),
    ("stocks",                   "Stock",                 ["id","warehouse_id","barcode","quantity","updated_at"],                 ["id","account_id","warehouse_id","sku_id","barcode","quantity","updated_at"]),
    ("orders",                   "Order",                 ["id","wb_order_id","delivery_type","supplier_status","wb_status","nm_id","article","price","created_at"], ["id","wb_order_id","order_uid","srid","delivery_type","nm_id","chrt_id","article","barcode","supplier_status","wb_status","price","converted_price","currency_code","warehouse_id","wb_office","required_meta","optional_meta","is_zero_order","created_at","updated_at","synced_at"]),
    ("supplies",                 "Supply",                ["id","wb_supply_id","name","supply_type","is_done","supply_created_at"],["id","wb_supply_id","name","supply_type","is_done","supply_created_at","closed_at","scan_dt","synced_at"]),
    ("ad_campaigns",             "AdCampaign",            ["id","wb_advert_id","name","campaign_type","status","daily_budget","start_time","end_time"], ["id","wb_advert_id","name","campaign_type","status","daily_budget","total_budget","start_time","end_time","created_at","updated_at","synced_at"]),
    ("promotions",               "Promotion",             ["id","wb_promotion_id","name","period_start","period_end","discount"],  ["id","wb_promotion_id","name","period_start","period_end","discount","synced_at"]),
    ("analytics_sales_funnels",  "AnalyticsSalesFunnel",  ["id","stat_date","nm_id","vendor_code","open_card","add_to_cart","orders","buyouts","conv_to_cart","cart_to_order"], ["id","account_id","stat_date","nm_id","vendor_code","brand","subject","open_card","add_to_cart","orders","orders_sum","buyouts","buyouts_sum","cancel_count","cancel_sum","conv_to_cart","cart_to_order"]),
    ("analytics_search_terms",   "AnalyticsSearchTerm",   ["id","stat_date","keyword","nm_id","orders","avg_position","frequency"],["id","account_id","stat_date","keyword","nm_id","orders","avg_position","frequency"]),
    ("reviews",                  "Review",                ["id","wb_review_id","nm_id","rating","was_viewed","is_answered","is_pinned","wb_created_at"], ["id","wb_review_id","nm_id","vendor_code","size","rating","text","photo_urls","video_urls","was_viewed","is_answered","answer_text","answer_at","is_pinned","is_archived","wb_created_at","synced_at"]),
    ("questions",                "Question",              ["id","wb_question_id","nm_id","was_viewed","is_answered","wb_created_at"], ["id","wb_question_id","nm_id","vendor_code","text","was_viewed","is_answered","answer_text","answer_at","wb_created_at","synced_at"]),
    ("chats",                    "Chat",                  ["id","wb_chat_id","buyer_id","order_id","last_message_at"],             ["id","wb_chat_id","buyer_id","order_id","last_message_at","created_at","updated_at"]),
    ("return_claims",            "ReturnClaim",           ["id","wb_claim_id","order_id","nm_id","status","wb_created_at"],        ["id","wb_claim_id","order_id","nm_id","status","reason","response_text","wb_created_at","responded_at","synced_at"]),
    ("account_balances",         "AccountBalance",        ["id","currency","current","for_withdraw","snapshot_at"],               ["id","account_id","currency","current","for_withdraw","snapshot_at"]),
    ("sales_reports",            "SalesReport",           ["id","wb_report_id","date_from","date_to","net_payable","synced_at"],   ["id","wb_report_id","date_from","date_to","report_created_at","total_sales","total_returns","total_commission","total_delivery","total_penalty","net_payable","synced_at"]),
    ("sync_tasks",               "SyncTask",              ["id","task_type","wb_task_id","status","created_at","completed_at"],    ["id","account_id","task_type","wb_task_id","status","file_url","created_at","completed_at"]),
]

CONTROLLER_TEMPLATE = '''module RawWb
  class {ClassName}Controller < BaseController
    before_action :set_{var},  only: [:show, :update, :destroy]

    def index
      @{vars} = {ModelClass}.all
      @{vars} = @{vars}.where(account_id: params[:account_id]) if params[:account_id].present?
      @{vars} = @{vars}.page(params[:page]).per(params[:per_page] || 20)
    end

    def show; end

    def create
      @{var} = {ModelClass}.new({var}_params)
      @{var}.save!
      @message = 'Created successfully'
      render :show, status: :created
    end

    def update
      @{var}.update!({var}_params)
      @message = 'Updated successfully'
      render :show
    end

    def destroy
      @{var}.destroy!
      @message = 'Deleted successfully'
      render json: {{ success: true, data: nil, message: @message }}
    end

    private

    def set_{var}
      @{var} = {ModelClass}.find(params[:id])
    end

    def {var}_params
      params.require(:{var}).permit!
    end
  end
end
'''

INDEX_TEMPLATE = '''json.success true
json.data do
  json.{vars} do
    json.array! @{vars} do |{var}|
{index_fields}
    end
  end
  json.meta do
    json.current_page @{vars}.current_page
    json.total_pages  @{vars}.total_pages
    json.total_count  @{vars}.total_count
  end
end
json.message @message || 'ok'
'''

SHOW_TEMPLATE = '''json.success true
json.data do
  json.{var} do
{show_fields}
  end
end
json.message @message || 'ok'
'''

def fields_block(var, fields, indent=6):
    pad = " " * indent
    return "\n".join(f"{pad}json.{f} @{var}.{f}" for f in fields)


for (name, model, index_fields, show_fields) in RESOURCES:
    var = name.rstrip("s") if not name.endswith("ies") else name[:-3] + "y"
    # Fix pluralization edge cases
    var = var.replace("analyticss_sales_funnel", "analytics_sales_funnel")
    var = var.replace("analyticss_search_term", "analytics_search_term")
    # Derive singular from plural more carefully
    singular_map = {
        "platforms": "platform",
        "seller_accounts": "seller_account",
        "categories": "category",
        "subjects": "subject",
        "products": "product",
        "product_skus": "product_sku",
        "product_prices": "product_price",
        "warehouses": "warehouse",
        "stocks": "stock",
        "orders": "order",
        "supplies": "supply",
        "ad_campaigns": "ad_campaign",
        "promotions": "promotion",
        "analytics_sales_funnels": "analytics_sales_funnel",
        "analytics_search_terms": "analytics_search_term",
        "reviews": "review",
        "questions": "question",
        "chats": "chat",
        "return_claims": "return_claim",
        "account_balances": "account_balance",
        "sales_reports": "sales_report",
        "sync_tasks": "sync_task",
    }
    var = singular_map[name]
    class_name = "".join(w.capitalize() for w in name.split("_"))

    full_model = f"RawWb::{model}"

    # Controller
    ctl_content = CONTROLLER_TEMPLATE.format(
        ClassName=class_name,
        var=var,
        vars=name,
        ModelClass=full_model,
    )
    with open(f"{CTL_DIR}/{name}_controller.rb", "w") as f:
        f.write(ctl_content)

    # Views directory
    view_subdir = f"{VIEW_DIR}/{name}"
    os.makedirs(view_subdir, exist_ok=True)

    # index.json.jbuilder
    idx_fields = fields_block(var, index_fields)
    idx_content = INDEX_TEMPLATE.format(vars=name, var=var, index_fields=idx_fields)
    with open(f"{view_subdir}/index.json.jbuilder", "w") as f:
        f.write(idx_content)

    # show.json.jbuilder
    show_flds = fields_block(var, show_fields)
    show_content = SHOW_TEMPLATE.format(var=var, show_fields=show_flds)
    with open(f"{view_subdir}/show.json.jbuilder", "w") as f:
        f.write(show_content)

print(f"Generated controllers and views for {len(RESOURCES)} resources")
