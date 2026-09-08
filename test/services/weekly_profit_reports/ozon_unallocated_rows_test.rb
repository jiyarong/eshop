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
      { type_id: 96, type_name: "加速审核费 / Ускоренная проверка / AcceleratedReviewCollection (Ozon type 96)", amount: 3.5 },
      { type_id: 41, type_name: "PPC 广告费 / Оплата за клики (Ozon type 41)", amount: 5.0 },
      { type_id: 54, type_name: "推广费 / Продвижение / Promotion (Ozon type 54)", amount: 7.0 },
      { type_id: 999, type_name: "CustomFee (Ozon type 999)", amount: 3.4 }
    ], WeeklyProfitReports::OzonUnallocatedRows.normalize(unallocated)
  end

  test "uses a readable category for type 101 when Ozon omits the name" do
    rows = WeeklyProfitReports::OzonUnallocatedRows.normalize(
      total: -9_240,
      rows: [{ type_id: 101, type_name: nil, amount: -9_240 }]
    )

    assert_equal "其他平台费用 / Прочие расходы Ozon (Ozon type 101)", rows.first[:type_name]
    assert_equal(-9_240.0, rows.first[:amount])
  end
end
