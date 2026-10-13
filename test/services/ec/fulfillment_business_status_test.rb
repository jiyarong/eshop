require "test_helper"

class Ec::FulfillmentBusinessStatusTest < ActiveSupport::TestCase
  def resolve(**attributes)
    defaults = { platform: "wb", status: "processing", source_status: nil, source_substatus: nil }
    Ec::FulfillmentBusinessStatus.resolve(**defaults.merge(attributes))
  end

  def business(**attributes)
    resolve(**attributes).business_status
  end

  def return_status(**attributes)
    resolve(**attributes).return_business_status
  end

  def return_record(source_status: nil, process_status: "unknown", returned_to_seller: false, at: Time.zone.parse("2026-09-01 10:00"), id: 1)
    { id: id, at: at, source_status: source_status, process_status: process_status, returned_to_seller: returned_to_seller }
  end

  test "vocabulary matches the design" do
    assert_equal %w[awaiting_assembly awaiting_dispatch in_delivery delivered cancelled needs_review],
      Ec::FulfillmentBusinessStatus::BUSINESS_STATUSES
    assert_equal %w[none expected at_platform_side returning_to_seller received_by_seller no_physical_return],
      Ec::FulfillmentBusinessStatus::RETURN_STATUSES
  end

  test "maps WB marketplace statuses" do
    {
      [ "waiting", "new", "processing" ] => "awaiting_assembly",
      [ "waiting", "confirm", "processing" ] => "awaiting_dispatch",
      [ "waiting", "complete", "processing" ] => "in_delivery",
      [ "sorted", "complete", "shipped" ] => "in_delivery",
      [ "ready_for_pickup", "complete", "shipped" ] => "in_delivery",
      [ "postponed_delivery", "complete", "shipped" ] => "in_delivery",
      [ "accepted_by_carrier", "complete", "shipped" ] => "in_delivery",
      [ "sent_to_carrier", "complete", "shipped" ] => "in_delivery",
      [ "sold", "complete", "delivered" ] => "delivered",
      [ "canceled", "complete", "cancelled" ] => "cancelled",
      [ "canceled_by_client", "complete", "cancelled" ] => "cancelled",
      [ "declined_by_client", "new", "cancelled" ] => "cancelled",
      [ "defect", "complete", "cancelled" ] => "cancelled",
      [ "canceled_by_carrier", "complete", "cancelled" ] => "cancelled",
      [ "waiting", "cancel", "cancelled" ] => "cancelled",
      [ nil, nil, "processing" ] => "needs_review"
    }.each do |(source_status, source_substatus, status), expected|
      assert_equal expected, business(platform: "wb", status: status, source_status: source_status,
        source_substatus: source_substatus), [ source_status, source_substatus, status ].inspect
    end
  end

  test "WB statistics evidence outranks a stuck waiting status but not a cancel class status" do
    assert_equal "delivered",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "sale")
    assert_equal "delivered",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "return")
    assert_equal "cancelled",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "cancel")
    assert_equal "cancelled",
      business(platform: "wb", source_status: "canceled_by_client", source_substatus: "complete",
        status: "returned", stats_evidence: "return")
    assert_equal "awaiting_assembly",
      business(platform: "wb", source_status: "waiting", source_substatus: "new", stats_evidence: "order_only")
  end

  test "WB sold and returned orders without a platform status are delivered" do
    assert_equal "delivered", business(platform: "wb", status: "delivered")
    assert_equal "delivered", business(platform: "wb", status: "returned", source_status: "sold", source_substatus: "complete")
  end

  test "maps Ozon posting statuses" do
    {
      [ "awaiting_packaging", "posting_created" ] => "awaiting_assembly",
      [ "awaiting_deliver", "posting_transferring_to_delivery" ] => "awaiting_dispatch",
      [ "awaiting_delivery", nil ] => "awaiting_dispatch",
      [ "delivering", "posting_in_pickup_point" ] => "in_delivery",
      [ "delivering", "posting_on_way_to_city" ] => "in_delivery",
      [ "delivering", "posting_in_carriage" ] => "in_delivery",
      [ "delivering", "posting_transferred_to_courier_service" ] => "in_delivery",
      [ "driver_pickup", nil ] => "in_delivery",
      [ "sent_by_seller", nil ] => "in_delivery",
      [ "delivered", "posting_received" ] => "delivered",
      [ "delivered", "posting_delivered" ] => "delivered",
      [ "cancelled", "posting_canceled" ] => "cancelled",
      [ "not_accepted", nil ] => "cancelled",
      [ "delivering", "posting_returned_to_warehouse" ] => "cancelled",
      [ "awaiting_approve", nil ] => "needs_review",
      [ "arbitration", nil ] => "needs_review"
    }.each do |(source_status, source_substatus), expected|
      assert_equal expected, business(platform: "ozon", source_status: source_status,
        source_substatus: source_substatus), [ source_status, source_substatus ].inspect
    end
  end

  test "maps Ozon return statuses" do
    {
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
      "PotentiallyLost" => "no_physical_return",
      "SomethingNew" => "at_platform_side"
    }.each do |source_status, expected|
      assert_equal expected,
        return_status(platform: "ozon", source_status: "delivered", source_substatus: "posting_received",
          status: "delivered", returns: [ return_record(source_status: source_status) ]), source_status
    end
  end

  test "maps WB goods return records" do
    base = { platform: "wb", source_status: "sold", source_substatus: "complete", status: "delivered" }
    assert_equal "received_by_seller",
      return_status(**base, returns: [ return_record(source_status: "Выдано", process_status: "completed") ])
    assert_equal "received_by_seller",
      return_status(**base, returns: [ return_record(returned_to_seller: true) ])
    assert_equal "returning_to_seller",
      return_status(**base, returns: [ return_record(source_status: "Готов к выдаче", process_status: "ready_for_seller_pickup") ])
    assert_equal "at_platform_side",
      return_status(**base, returns: [ return_record(source_status: "В пути в пвз", process_status: "unknown") ])
  end

  test "uses the latest valid return and falls back to no physical return" do
    base = { platform: "ozon", source_status: "delivered", source_substatus: "posting_received", status: "delivered" }
    older = return_record(source_status: "ReceivedBySeller", id: 1, at: Time.zone.parse("2026-09-01"))
    newer_cancelled = return_record(source_status: "Cancelled", id: 2, at: Time.zone.parse("2026-09-05"))
    newest_active = return_record(source_status: "MovingToOzon", id: 3, at: Time.zone.parse("2026-09-09"))

    assert_equal "received_by_seller", return_status(**base, returns: [ older, newer_cancelled ])
    assert_equal "at_platform_side", return_status(**base, returns: [ older, newer_cancelled, newest_active ])
    assert_equal "no_physical_return", return_status(**base, returns: [ newer_cancelled ])
  end

  test "marks cancelled fulfillments that left the warehouse as expected" do
    base = { platform: "wb", source_status: "canceled_by_client", source_substatus: "complete", status: "cancelled" }
    assert_equal "expected", return_status(**base, dispatched: true)
    assert_equal "none", return_status(**base, dispatched: false)
    assert_equal "none",
      return_status(platform: "wb", source_status: "sold", source_substatus: "complete", status: "delivered", dispatched: true)
  end

  test "WB return evidence without a return record means the goods are on the platform side" do
    base = { platform: "wb", source_status: "canceled_by_client", source_substatus: "complete", status: "returned",
             stats_evidence: "return", dispatched: true }
    assert_equal "at_platform_side", return_status(**base)
    assert_equal "at_platform_side",
      return_status(platform: "wb", source_status: "sold", source_substatus: "complete", status: "returned")
  end

  test "dispatch evidence is only evaluated for cancelled fulfillments without a return" do
    calls = 0
    probe = -> { calls += 1; true }

    return_status(platform: "wb", source_status: "sold", source_substatus: "complete", status: "delivered", dispatched: probe)
    assert_equal 0, calls

    return_status(platform: "wb", source_status: "canceled_by_client", source_substatus: "complete",
      status: "cancelled", dispatched: probe)
    assert_equal 1, calls
  end

  test "resolve returns both axes together" do
    result = resolve(platform: "ozon", source_status: "delivered", source_substatus: "posting_received",
      status: "delivered", returns: [ return_record(source_status: "ReceivedBySeller") ])

    assert_equal "delivered", result.business_status
    assert_equal "received_by_seller", result.return_business_status
  end
end
