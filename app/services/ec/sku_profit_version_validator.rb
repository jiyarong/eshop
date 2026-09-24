module Ec
  class SkuProfitVersionValidator
    def self.call(version) = new(version).call

    def initialize(version)
      @version = version
    end

    def call
      return false unless version.valid?

      SkuProfitVersionRecalculator.call(version).each do |context, result|
        result.fetch(:errors, []).each { |error| context.errors.add(:calculation_status, error) }
      end

      version.contexts.all? { |context| context.errors.empty? }
    end

    private

    attr_reader :version
  end
end
