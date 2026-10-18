module Ec
  module PalletPlans
    class Error < StandardError
      attr_reader :key, :details

      def initialize(key, **details)
        @key, @details = key, details
        super(I18n.t("pallet_workbench.errors.#{key}", **details))
      end
    end
  end
end
