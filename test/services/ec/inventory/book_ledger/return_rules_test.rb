require "test_helper"

class Ec::Inventory::BookLedger::ReturnRulesTest < ActiveSupport::TestCase
  Rules = Ec::Inventory::BookLedger::ReturnRules

  test "maps Ozon return statuses to a location or no reversal" do
    assert_equal :transit, Rules.location("ozon", "MovingToOzon")
    assert_equal :platform, Rules.location("ozon", "ReturnedToOzon")
    assert_equal :transit, Rules.location("ozon", "MovingToSeller")
    assert_equal :transit, Rules.location("ozon", "ReadyForSeller")
    assert_equal :own, Rules.location("ozon", "ReceivedBySeller")
    %w[OnSellerApproval WaitingShipment Approved MoneyReturned PartialCompensationReturned
       Cancelled CancelledDisputeNotOpen Rejected].each do |status|
      assert_nil Rules.location("ozon", status), status
    end
    assert_nil Rules.location("ozon", nil)
  end

  test "maps WB goods-return statuses: issued is own side, everything else is on its way" do
    assert_equal :own, Rules.location("wb", "Выдано")
    assert_equal :transit, Rules.location("wb", "В пути в пвз")
    assert_equal :transit, Rules.location("wb", "Готов к выдаче")
    assert_nil Rules.location("wb", nil)
  end

  test "classifies unsellable returns by Ozon reason and WB return type" do
    assert Rules.unsellable?("ozon", reason: "Товар не работает / брак", return_type: nil)
    assert Rules.unsellable?("ozon", reason: "Упаковка и товар повреждены", return_type: nil)
    assert Rules.unsellable?("ozon", reason: "Товар поддельный", return_type: nil)
    assert_not Rules.unsellable?("ozon", reason: "Покупатель передумал", return_type: nil)
    assert Rules.unsellable?("wb", reason: nil, return_type: "Возврат брака")
    assert_not Rules.unsellable?("wb", reason: nil, return_type: "Возврат неверного вложения")
    assert_not Rules.unsellable?("wb", reason: nil, return_type: nil)
  end
end
