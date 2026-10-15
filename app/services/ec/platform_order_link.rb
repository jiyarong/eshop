module Ec
  # Address of an order inside the platform's seller cabinet, or nil when the cabinet has no page that opens
  # that specific order. Verified against the live cabinets (2026-10):
  #
  # * Ozon FBS: the orders list opens the posting card as a modal when `postingDetails=<posting_number>` is set,
  #   for any status and age. FBO postings have no card at all.
  # * Wildberries: FBS assembly tasks are only listed per status tab; there is no address for one task, so the
  #   link goes to the tab that currently holds the order and the task number has to be searched on that list.
  module PlatformOrderLink
    OZON_FBS_URL = "https://seller.ozon.ru/app/postings/fbs".freeze
    WB_FBS_TABS_URL = "https://seller.wildberries.ru/marketplace-orders-fbs".freeze
    WB_FBS_TAB_BY_BUSINESS_STATUS = {
      "awaiting_assembly" => "new-tasks",
      "awaiting_dispatch" => "on-assembly",
      "in_delivery" => "on-delivery",
      "delivered" => "archived",
      "returned" => "archived",
      "cancelled" => "canceled"
    }.freeze

    module_function

    # Opens the order itself: only Ozon FBS postings have such a page.
    def exact_url(order)
      return unless order.platform == "ozon"

      fulfillment = order.fulfillments.find { |candidate| candidate.fulfillment_type == "fbs" }
      posting_number = fulfillment&.external_fulfillment_id.presence
      return unless posting_number

      "#{OZON_FBS_URL}?#{{ postingDetails: posting_number }.to_query}"
    end

    # Opens the cabinet list that holds the order (WB FBS only).
    def list_url(order)
      return unless order.platform == "wb"

      fulfillment = order.fulfillments.find { |candidate| candidate.fulfillment_type == "fbs" }
      return unless fulfillment

      tab = WB_FBS_TAB_BY_BUSINESS_STATUS[fulfillment.business_status]
      tab ? "#{WB_FBS_TABS_URL}/#{tab}" : nil
    end
  end
end
