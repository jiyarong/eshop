module RawWb
  module OrderStatus
    WB_STATUS_MAP = {
      "waiting" => "processing",
      "sorted" => "shipped",
      "ready_for_pickup" => "shipped",
      "sold" => "delivered",
      "canceled" => "cancelled",
      "cancelled" => "cancelled",
      "canceled_by_client" => "cancelled",
      "declined_by_client" => "cancelled",
      "defect" => "cancelled",
      "returned" => "returned"
    }.freeze

    SUPPLIER_STATUS_MAP = {
      "new" => "processing",
      "confirm" => "processing",
      "complete" => "shipped",
      "cancel" => "cancelled",
      "cancelled" => "cancelled",
      "returned" => "returned"
    }.freeze

    FINAL_WB_STATUSES = WB_STATUS_MAP.select { |_, status| %w[cancelled returned].include?(status) }.keys.freeze
    FINAL_SUPPLIER_STATUSES = SUPPLIER_STATUS_MAP.select { |_, status| %w[cancelled returned].include?(status) }.keys.freeze

    def self.normalize(wb_status:, supplier_status:)
      WB_STATUS_MAP[wb_status.to_s] || SUPPLIER_STATUS_MAP[supplier_status.to_s] || "unknown"
    end
  end
end
