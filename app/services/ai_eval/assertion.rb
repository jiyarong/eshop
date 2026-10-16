# frozen_string_literal: true

module AiEval
  class Assertion
    OPERATORS = %w[eq one_of include exclude exists numeric_close range subset jsonpath semantic_fact].freeze

    def self.call(actual:, assertion:)
      new(actual:, assertion:).call
    end

    def initialize(actual:, assertion:)
      @actual = normalize(actual)
      @assertion = assertion.is_a?(Hash) ? assertion.deep_stringify_keys : {}
    end

    def call
      operator = @assertion.fetch("operator")
      weight = Float(@assertion.fetch("weight", 1))
      raise ArgumentError, "weight must be finite and non-negative" unless weight.finite? && weight >= 0
      raise ArgumentError, "unsupported operator: #{operator}" unless OPERATORS.include?(operator)
      validate_configuration!(operator)

      @values = resolve(@assertion.fetch("path", "$"))
      @found = !@values.empty?
      actual = @multiple ? @values : @values.first
      if operator == "semantic_fact"
        return result(operator:, weight:, actual:, status: "unsupported", passed: nil,
          error: "semantic_fact_not_implemented")
      end

      passed = matches?(operator, actual)
      result(operator:, weight:, actual:, status: passed ? "passed" : "failed", passed:)
    rescue KeyError, ArgumentError, TypeError => error
      result(operator:, weight: 0.0, actual:, status: "error", passed: false, error: error.message)
    end

    private

    def normalize(value)
      case value
      when Hash then value.deep_stringify_keys
      when Array then value.map { |item| normalize(item) }
      else value
      end
    end

    def result(operator:, weight:, actual:, status:, passed:, error: nil)
      {
        id: @assertion["id"] || "#{operator}:#{@assertion.fetch("path", "$")}",
        path: @assertion.fetch("path", "$"), operator:, weight:,
        category: @assertion.fetch("category", "uncategorized"),
        severity: @assertion.fetch("severity", "normal"),
        expected: @assertion["expected"], actual:, found: @found || false,
        status:, passed:, evidence: @assertion["evidence"], error:
      }
    end

    def matches?(operator, actual)
      expected = @assertion["expected"]
      if operator == "exists"
        raise ArgumentError, "exists expected must be boolean" unless [true, false].include?(@assertion.fetch("expected", true))
        return @found == @assertion.fetch("expected", true)
      end
      return @found if operator == "jsonpath" && !@assertion.key?("expected")
      raise ArgumentError, "expected is required" unless @assertion.key?("expected")
      return false unless @found

      case operator
      when "eq", "jsonpath" then actual == expected
      when "one_of"
        raise ArgumentError, "one_of requires a scalar actual and an array of choices" if actual.is_a?(Array) || actual.is_a?(Hash) || !expected.is_a?(Array)
        expected.include?(actual)
      when "include" then include?(actual, expected)
      when "exclude" then (expected.is_a?(Array) ? expected : [expected]).none? { |item| include?(actual, item) }
      when "subset" then subset?(actual, expected)
      when "numeric_close"
        number = finite_number(actual)
        target = finite_number(expected)
        tolerance = finite_number(@assertion.fetch("tolerance", 0.000001))
        relative = finite_number(@assertion.fetch("relative_tolerance", 0))
        raise ArgumentError, "tolerances must be non-negative" if tolerance < 0 || relative < 0
        (number - target).abs <= [tolerance, target.abs * relative].max
      when "range"
        number = finite_number(actual)
        bounds = expected.is_a?(Array) ? { "min" => expected[0], "max" => expected[1] } : expected
        raise ArgumentError, "range requires min or max" unless bounds.is_a?(Hash) && (bounds.key?("min") || bounds.key?("max"))
        minimum = bounds["min"]
        maximum = bounds["max"]
        lower = minimum.nil? || (bounds.fetch("inclusive_min", true) ? number >= finite_number(minimum) : number > finite_number(minimum))
        upper = maximum.nil? || (bounds.fetch("inclusive_max", true) ? number <= finite_number(maximum) : number < finite_number(maximum))
        lower && upper
      end
    end

    def validate_configuration!(operator)
      expected = @assertion["expected"]
      if operator == "exists"
        raise ArgumentError, "exists expected must be boolean" unless [true, false].include?(@assertion.fetch("expected", true))
      elsif !%w[jsonpath semantic_fact].include?(operator)
        raise ArgumentError, "expected is required" unless @assertion.key?("expected")
      end
      if operator == "one_of"
        raise ArgumentError, "one_of requires scalar choices" unless expected.is_a?(Array) && expected.any? && expected.none? { |item| item.is_a?(Array) || item.is_a?(Hash) }
      elsif operator == "numeric_close"
        finite_number(expected)
        %w[tolerance relative_tolerance].each do |key|
          raise ArgumentError, "tolerances must be non-negative" if @assertion.key?(key) && finite_number(@assertion[key]) < 0
        end
      elsif operator == "range"
        bounds = expected.is_a?(Array) && expected.length == 2 ? { "min" => expected[0], "max" => expected[1] } : expected
        raise ArgumentError, "range requires min or max" unless bounds.is_a?(Hash) && (bounds["min"] || bounds["max"])
        %w[min max].each { |key| finite_number(bounds[key]) unless bounds[key].nil? }
        raise ArgumentError, "range bounds are reversed" if bounds["min"] && bounds["max"] && bounds["min"] > bounds["max"]
      end
    end

    def include?(actual, expected)
      case actual
      when String then expected.is_a?(String) && actual.include?(expected)
      when Array then expected.is_a?(Array) ? expected.all? { |item| actual.include?(item) } : actual.include?(expected)
      when Hash then expected.is_a?(Hash) ? subset?(actual, expected) : actual.key?(expected.to_s)
      else false
      end
    end

    def subset?(actual, expected)
      case expected
      when Hash
        actual.is_a?(Hash) && expected.all? { |key, value| actual.key?(key) && subset?(actual[key], value) }
      when Array
        actual.is_a?(Array) && expected.all? { |item| actual.any? { |candidate| subset?(candidate, item) } }
      else actual == expected
      end
    end

    def finite_number(value)
      raise ArgumentError, "value must be numeric" unless value.is_a?(Numeric)
      number = Float(value)
      raise ArgumentError, "value must be finite" unless number.finite?
      number
    end

    # Safe JSONPath subset: $.key, [index], ['key'], ["key"], [*]. JSON
    # Pointer paths are supported as well. Filters/scripts are rejected.
    def tokens(path)
      raise ArgumentError, "path must be a string" unless path.is_a?(String)
      return [] if path == "$" || path == ""
      return path.split("/", -1).drop(1).map { |part| part.gsub("~1", "/").gsub("~0", "~") } if path.start_with?("/")
      raise ArgumentError, "JSONPath must start with $" unless path.start_with?("$")

      remaining = path[1..]
      result = []
      until remaining.empty?
        match = remaining.match(/\A(?:\.([A-Za-z_][A-Za-z0-9_\-]*)|\[(\d+)\]|\[(?:'([^']*)'|"([^"]*)")\]|\[(\*)\])/)
        raise ArgumentError, "unsupported JSONPath expression" unless match
        result << (match[1] || match[2] || match[3] || match[4] || :*)
        remaining = remaining[match[0].length..]
      end
      result
    end

    def resolve(path)
      path_tokens = tokens(path)
      @multiple = path_tokens.include?(:*)
      path_tokens.reduce([@actual]) do |values, token|
        values.flat_map do |value|
          if token == :*
            value.is_a?(Hash) ? value.values : (value.is_a?(Array) ? value : [])
          elsif value.is_a?(Hash)
            value.key?(token) ? [value[token]] : []
          elsif value.is_a?(Array) && token.to_s.match?(/\A\d+\z/) && token.to_i < value.length
            [value[token.to_i]]
          else
            []
          end
        end
      end
    end

    Evaluator = self
  end
end
