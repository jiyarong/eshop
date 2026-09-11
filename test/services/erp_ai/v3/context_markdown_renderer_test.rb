require "test_helper"

class ErpAI::V3::ContextMarkdownRendererTest < ActiveSupport::TestCase
  test "renders arrays with flat values hashes as tables" do
    markdown = ErpAI::V3::ContextMarkdownRenderer.call(
      data: {
        schema_version: 3,
        sku_code: "DJ001",
        period: {
          from: "2026-08-10",
          to: "2026-09-06",
          as_of: "2026-09-11",
          time_zone: "Asia/Shanghai",
          week_starts_on: "monday"
        },
        sales_funnel: {
          store_listing: {
            store_listings: [
              {
                platform: "ozon",
                listing_label: "Hydraulic | crane",
                rows_per_week: [
                  {
                    period_key: "P-1",
                    period_from: "2026-07-13",
                    period_to: "2026-08-09",
                    values: {
                      product_card_views: 700,
                      cart_rate: 9.57,
                      net_sales: 6
                    },
                    available_metrics: %w[product_card_views cart_rate net_sales]
                  },
                  {
                    period_key: "P0",
                    period_from: "2026-08-10",
                    period_to: "2026-09-06",
                    values: {
                      product_card_views: 5707,
                      cart_rate: 9.58,
                      net_sales: 51
                    },
                    available_metrics: []
                  }
                ]
              }
            ]
          }
        }
      }
    )

    assert_includes markdown,
      "| period_key | period_from | period_to | product_card_views | cart_rate | net_sales | available_metrics |"
    assert_includes markdown,
      "| P-1 | 2026-07-13 | 2026-08-09 | 700 | 9.57 | 6 | product_card_views, cart_rate, net_sales |"
    assert_includes markdown,
      "| P0 | 2026-08-10 | 2026-09-06 | 5707 | 9.58 | 51 |  |"
    assert_includes markdown, "| listing_label | Hydraulic \\| crane |"
    assert_not_includes markdown, "- **product_card_views:** 700"
  end

  test "keeps complex arrays expanded instead of flattening unsafe nested data" do
    markdown = ErpAI::V3::ContextMarkdownRenderer.call(
      data: {
        schema_version: 3,
        sku_code: "DJ001",
        period: {},
        lifecycle: {
          key_events: {
            events: [
              {
                id: 1,
                event_type: "first_sale",
                content: {
                  order: { id: 100, quantity: 1 }
                }
              }
            ]
          }
        }
      }
    )

    assert_includes markdown, "##### Item 1"
    assert_includes markdown, "###### content"
    assert_includes markdown, "| key | value |"
    assert_includes markdown, "| id | 100 |"
    assert_includes markdown, "| quantity | 1 |"
  end

  test "renders operation actions as a log table with summaries" do
    markdown = ErpAI::V3::ContextMarkdownRenderer.call(
      data: {
        schema_version: 3,
        sku_code: "DJ001",
        period: {},
        operation_actions_full_period: [
          {
            action_id: 1,
            operated_at: "2026-08-10T03:13:51Z",
            operation_type: "listing_pricing",
            operation_type_label: "价格",
            platform: "ozon",
            store_name: "NEVASTAL",
            sku_code: "DJ001",
            sku_product_id: 113,
            platform_sku_id: "4821521797",
            operated_by_user_name: "Operator",
            record_by_system: true,
            diff_summary: ["营销价: 修改前: 100; 修改后: 120"],
            diff_result: {
              fields: {
                price: { from: 100, to: 120 }
              }
            }
          }
        ]
      }
    )

    assert_includes markdown,
      "| action_id | operated_at | operation_type | operation_type_label | platform | store_name | sku_code | sku_product_id | platform_sku_id | operated_by_user_name | record_by_system | diff_summary |"
    assert_includes markdown,
      "| 1 | 2026-08-10T03:13:51Z | listing_pricing | 价格 | ozon | NEVASTAL | DJ001 | 113 | 4821521797 | Operator | true | 营销价: 修改前: 100; 修改后: 120 |"
    assert_not_includes markdown, "#### diff_result"
    assert_not_includes markdown, "| from | 100 |"
  end
end
