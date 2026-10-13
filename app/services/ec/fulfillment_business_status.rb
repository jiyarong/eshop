module Ec
  # Flattens the platform specific order and return statuses of one fulfillment (posting) into two platform
  # neutral values: where the goods are in the delivery chain (business status) and where the returning goods
  # are (return business status). Pure functions: the caller (Updater) gathers the inputs.
  module FulfillmentBusinessStatus
    BUSINESS_STATUSES = %w[
      awaiting_assembly awaiting_dispatch in_delivery delivered returned cancelled needs_review
    ].freeze
    RETURN_STATUSES = %w[
      none expected at_platform_side returning_to_seller received_by_seller no_physical_return
    ].freeze

    Result = Data.define(:business_status, :return_business_status)

    WB_CANCEL_STATUSES = %w[canceled cancelled canceled_by_client declined_by_client defect canceled_by_carrier].freeze
    WB_CANCEL_SUBSTATUSES = %w[cancel cancelled cancel_carrier].freeze
    WB_DELIVERED_STATUSES = %w[sold returned].freeze
    WB_IN_DELIVERY_STATUSES = %w[sorted ready_for_pickup postponed_delivery accepted_by_carrier sent_to_carrier].freeze
    WB_WAITING_SUBSTATUSES = {
      "new" => "awaiting_assembly", "confirm" => "awaiting_dispatch", "complete" => "in_delivery"
    }.freeze

    OZON_CANCEL_STATUSES = %w[cancelled not_accepted].freeze
    # A posting handed to delivery and then returned to the Ozon warehouse is treated as cancelled; the dispatch
    # evidence then marks it as expected back.
    OZON_CANCEL_SUBSTATUSES = %w[posting_canceled posting_returned_to_warehouse].freeze
    OZON_DELIVERED_STATUSES = %w[delivered].freeze
    OZON_DELIVERED_SUBSTATUSES = %w[posting_received posting_delivered].freeze
    OZON_ASSEMBLY_STATUSES = %w[awaiting_packaging].freeze
    OZON_DISPATCH_STATUSES = %w[awaiting_deliver awaiting_delivery].freeze
    OZON_IN_DELIVERY_STATUSES = %w[delivering driver_pickup sent_by_seller].freeze
    OZON_IN_DELIVERY_SUBSTATUSES = %w[
      posting_transferred_to_courier_service posting_in_carriage posting_on_way_to_city posting_in_pickup_point
    ].freeze

    # Ozon return requests that were voided: they do not make a delivered posting a returned one. Every other Ozon
    # return status (and every WB goods return record) is an effective return.
    OZON_VOIDED_RETURN_STATUSES = %w[Cancelled CancelledDisputeNotOpen Rejected].freeze

    OZON_RETURN_STATES = {
      "ReceivedBySeller" => "received_by_seller",
      "MovingToSeller" => "returning_to_seller",
      "ReadyForSeller" => "returning_to_seller",
      "ArrivedAtReturnPlace" => "returning_to_seller",
      "OnSellerApproval" => "at_platform_side",
      "WaitingShipment" => "at_platform_side",
      "Approved" => "at_platform_side",
      "MovingToOzon" => "at_platform_side",
      "ReturnedToOzon" => "at_platform_side",
      "MoneyReturned" => "no_physical_return",
      "PartialCompensationReturned" => "no_physical_return",
      "Cancelled" => "no_physical_return",
      "CancelledDisputeNotOpen" => "no_physical_return",
      "Rejected" => "no_physical_return",
      "WriteOff" => "no_physical_return",
      "Utilized" => "no_physical_return",
      "PotentiallyLost" => "no_physical_return"
    }.freeze

    module_function

    def resolve(platform:, status:, source_status:, source_substatus:, stats_evidence: nil, returns: [], dispatched: false)
      business = business_status(
        platform: platform, status: status, source_status: source_status,
        source_substatus: source_substatus, stats_evidence: stats_evidence, returns: returns
      )
      Result.new(
        business_status: business,
        return_business_status: return_business_status(
          platform: platform, business_status: business, status: status, returns: returns,
          dispatched: dispatched, stats_evidence: stats_evidence
        )
      )
    end

    # A delivered fulfillment that has an effective return is `returned` (the buyer's return was accepted after the
    # goods were received). Cancelled, in delivery and the rest are never turned into `returned`.
    def business_status(platform:, status:, source_status:, source_substatus:, stats_evidence: nil, returns: [])
      source_status = source_status.to_s
      source_substatus = source_substatus.to_s
      base =
        if platform.to_s == "wb"
          wb_business_status(status.to_s, source_status, source_substatus, stats_evidence.to_s)
        else
          ozon_business_status(source_status, source_substatus)
        end
      return base unless base == "delivered"

      returned_after_delivery?(platform: platform, status: status, stats_evidence: stats_evidence, returns: returns) ? "returned" : base
    end

    def returned_after_delivery?(platform:, status:, stats_evidence:, returns:)
      return true if platform.to_s == "wb" && (status.to_s == "returned" || stats_evidence.to_s == "return")

      Array(returns).any? { |item| effective_return?(platform: platform, source_status: item[:source_status]) }
    end

    def effective_return?(platform:, source_status:)
      return true unless platform.to_s == "ozon"

      !source_status.to_s.in?(OZON_VOIDED_RETURN_STATUSES)
    end

    def wb_business_status(status, source_status, source_substatus, stats_evidence)
      if status == "cancelled" || stats_evidence == "cancel" ||
          source_status.in?(WB_CANCEL_STATUSES) || source_substatus.in?(WB_CANCEL_SUBSTATUSES)
        return "cancelled"
      end
      if stats_evidence.in?(%w[return sale]) || status.in?(%w[delivered returned]) ||
          source_status.in?(WB_DELIVERED_STATUSES)
        return "delivered"
      end
      return WB_WAITING_SUBSTATUSES.fetch(source_substatus, "needs_review") if source_status == "waiting"
      return "in_delivery" if source_status.in?(WB_IN_DELIVERY_STATUSES)

      "needs_review"
    end

    def ozon_business_status(source_status, source_substatus)
      return "cancelled" if source_status.in?(OZON_CANCEL_STATUSES) || source_substatus.in?(OZON_CANCEL_SUBSTATUSES)
      if source_status.in?(OZON_DELIVERED_STATUSES) || source_substatus.in?(OZON_DELIVERED_SUBSTATUSES)
        return "delivered"
      end
      return "awaiting_assembly" if source_status.in?(OZON_ASSEMBLY_STATUSES)
      return "awaiting_dispatch" if source_status.in?(OZON_DISPATCH_STATUSES)
      if source_status.in?(OZON_IN_DELIVERY_STATUSES) || source_substatus.in?(OZON_IN_DELIVERY_SUBSTATUSES)
        return "in_delivery"
      end

      "needs_review"
    end

    # State of one return record. Unknown Ozon statuses count as still in progress on the platform side.
    def return_state(platform:, source_status:, process_status:, returned_to_seller:)
      return OZON_RETURN_STATES.fetch(source_status.to_s, "at_platform_side") if platform.to_s == "ozon"

      if returned_to_seller || source_status.to_s == "Выдано" || process_status.to_s == "completed"
        return "received_by_seller"
      end
      return "returning_to_seller" if process_status.to_s == "ready_for_seller_pickup"

      "at_platform_side"
    end

    def return_business_status(platform:, business_status:, status:, returns:, dispatched:, stats_evidence: nil)
      states = Array(returns).sort_by { |item| [ item[:at].to_f, item[:id].to_i ] }.map do |item|
        return_state(
          platform: platform, source_status: item[:source_status], process_status: item[:process_status],
          returned_to_seller: item[:returned_to_seller]
        )
      end
      chosen = states.reject { |state| state == "no_physical_return" }.last || states.last
      return chosen if chosen

      return "at_platform_side" if platform.to_s == "wb" && (status.to_s == "returned" || stats_evidence.to_s == "return")
      return "none" unless business_status == "cancelled"

      # Only a cancelled fulfillment without a return needs to know whether it left the warehouse.
      dispatched = dispatched.call if dispatched.respond_to?(:call)
      dispatched ? "expected" : "none"
    end
  end
end
