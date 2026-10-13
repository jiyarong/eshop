module Ec
  # Physical stocktake view of one SKU's FBS fulfillments: quantity per (business status x return business status).
  # Order items are attributed to the SKU only through the hard ec_sku_products link.
  class InventoryFbsStatusMatrixQuery
    ORDER_ITEM_JOIN = SalesFunnelReports::SkuFunnelAnalysisQuery::ORDER_ITEM_JOIN
    NOT_LEFT_BUSINESS_STATUSES = %w[awaiting_assembly awaiting_dispatch needs_review cancelled].freeze
    EXPECTED_RETURN_STATUSES = {
      "awaiting_assembly" => %w[none],
      "awaiting_dispatch" => %w[none],
      "needs_review" => %w[none],
      "in_delivery" => %w[none],
      "delivered" => %w[none at_platform_side returning_to_seller received_by_seller no_physical_return],
      "cancelled" => %w[none expected at_platform_side returning_to_seller received_by_seller no_physical_return]
    }.freeze

    # not_left: still in the seller warehouse; left: left the warehouse; returned: left and came back.
    def self.kind(business_status, return_business_status)
      return "returned" if return_business_status == "received_by_seller"
      if return_business_status == "none" && business_status.in?(NOT_LEFT_BUSINESS_STATUSES)
        return "not_left"
      end

      "left"
    end

    def self.anomaly?(business_status, return_business_status)
      !EXPECTED_RETURN_STATUSES.fetch(business_status, []).include?(return_business_status)
    end

    def initialize(sku)
      @sku = sku
    end

    def call
      cells = quantities.map do |(business_status, return_business_status), quantity|
        {
          business_status: business_status,
          return_business_status: return_business_status,
          quantity: quantity.to_i,
          kind: self.class.kind(business_status, return_business_status),
          anomaly: self.class.anomaly?(business_status, return_business_status)
        }
      end
      cells.sort_by! do |cell|
        [
          Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES.index(cell[:business_status]).to_i,
          Ec::FulfillmentBusinessStatus::RETURN_STATUSES.index(cell[:return_business_status]).to_i
        ]
      end

      { cells: cells, summary: summary(cells) }
    end

    private

    def quantities
      Ec::OrderItem
        .joins(:fulfillment)
        .joins(ORDER_ITEM_JOIN)
        .where(ec_sku_products: { sku_code: @sku.sku_code })
        .where(ec_order_fulfillments: { fulfillment_type: "fbs" })
        .group("ec_order_fulfillments.business_status", "ec_order_fulfillments.return_business_status")
        .sum("ec_order_items.quantity")
    end

    def summary(cells)
      by_kind = cells.group_by { |cell| cell[:kind] }.transform_values { |list| list.sum { |cell| cell[:quantity] } }
      {
        departed_quantity: by_kind.fetch("left", 0) + by_kind.fetch("returned", 0),
        not_departed_quantity: by_kind.fetch("not_left", 0),
        returned_quantity: by_kind.fetch("returned", 0),
        anomaly_quantity: cells.select { |cell| cell[:anomaly] }.sum { |cell| cell[:quantity] },
        total_quantity: cells.sum { |cell| cell[:quantity] }
      }
    end
  end
end
