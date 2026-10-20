module Ec
  class SkuProfitVersionValidator
    def self.call(version) = new(version).call

    def initialize(version)
      @version = version
    end

    def call
      return false unless version.valid?

      hidden = Ec::SkuScenarioVisibility.hidden_keys_for(version.sku)
      SkuProfitVersionRecalculator.call(version).each do |context, result|
        next if hidden.include?(scenario_key(context))

        result.fetch(:errors, []).each { |error| context.errors.add(:calculation_status, error) }
      end

      version.contexts.all? { |context| hidden.include?(scenario_key(context)) || context.errors.empty? }
    end

    private

    attr_reader :version

    # A scenario the SKU has hidden is not part of what a published version promises.
    def scenario_key(context)
      Ec::SkuProfitStandardContexts.key_for(context.attributes.slice(*Ec::SkuProfitStandardContexts::IDENTITY_KEYS))
    end
  end
end
