require "test_helper"

# Every figure a source cell of the pricing workbench can fetch says which data it comes from ("Basis: ...") and
# how it is worked out, so a person can check it by hand.
class ProfitPredictionSourceBasisTest < ActiveSupport::TestCase
  SHARED = %i[actual_selling_price wb_logistics_tariffs ozon_logistics_tariffs ozon_cross_dock].freeze
  PER_PLATFORM = %i[actual_return_rate actual_logistics actual_acquiring actual_storage actual_advertising official_commission].freeze
  PREFIX = { zh: "口径：", en: "Basis: ", ru: "Основа: " }.freeze

  PREFIX.each do |locale, prefix|
    test "the data basis of every source is written in #{locale}, scope first and then how to check it" do
      basis = I18n.t("reports.profit_prediction.source_basis", locale: locale)

      SHARED.each do |key|
        entry = basis.fetch(key)
        assert entry[:scope].start_with?(prefix), "#{locale} #{key} scope"
        assert_operator entry[:how].length, :>, 80, "#{locale} #{key} how"
      end
      PER_PLATFORM.each do |key|
        %i[wb ozon].each do |platform|
          scope = basis.fetch(key).fetch(:"#{platform}_scope")
          how = basis.fetch(key).fetch(:"#{platform}_how")
          assert scope.start_with?(prefix), "#{locale} #{key} #{platform} scope"
          assert_operator how.length, :>, 80, "#{locale} #{key} #{platform} how"
        end
      end
    end
  end
end
