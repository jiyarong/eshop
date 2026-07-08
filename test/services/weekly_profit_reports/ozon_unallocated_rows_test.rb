require "test_helper"

class WeeklyProfitReports::OzonUnallocatedRowsTest < ActiveSupport::TestCase
  test "normalize groups rows by type and keeps only orphaned ad rows" do
    unallocated = {
      total: 20.4,
      rows: [
        { type_id: 96, type_name: "AcceleratedReviewCollection", amount: 1.2 },
        { type_id: 96, type_name: "AcceleratedReviewCollection", amount: 2.3 },
        { type_id: 41, type_name: "PPC", amount: 4.0 },
        { type_id: 41, type_name: "PPC", amount: 5.0, orphaned: true },
        { type_id: 54, type_name: "Promotion", amount: 6.0 },
        { type_id: 54, type_name: "Promotion", amount: 7.0, orphaned: true },
        { type_id: 999, type_name: "CustomFee", amount: 3.4 }
      ]
    }

    assert_equal [
      { type_id: 96, type_name: "Ускоренная проверка (AcceleratedReviewCollection)", amount: 3.5 },
      { type_id: 41, type_name: "PPC (нет данных Performance)", amount: 5.0 },
      { type_id: 54, type_name: "Продвижение (нет данных Performance)", amount: 7.0 },
      { type_id: 999, type_name: "type_id=999", amount: 3.4 }
    ], WeeklyProfitReports::OzonUnallocatedRows.normalize(unallocated)
  end
end
