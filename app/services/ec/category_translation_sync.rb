module Ec
  class CategoryTranslationSync
    BATCH_SIZE = 10

    SYSTEM_PROMPT = <<~PROMPT.squish.freeze
      你是电商平台类目翻译 AI Agent。把平台原始类目名称翻译成中文、英文和俄文。
      每次最多会收到 10 个类目。只输出严格 JSON，格式为 {"categories":[{"id":1,"name_cn":"中文","name_en":"English","name_ru":"Русский"}]}。
      不要输出 Markdown、解释、寒暄或额外字段。SKU、品牌、数字和专有名词应保持准确。
    PROMPT

    def self.translate_pending_for_source(source, client: ErpAI::DefaultClient.new)
      new(client: client).call(Ec::Category.where(source: source).translation_pending)
    end

    def initialize(client: ErpAI::DefaultClient.new)
      @client = client
    end

    def call(categories)
      each_batch(categories) do |batch|
        translate_batch(batch)
      end
    end

    private

    attr_reader :client

    def each_batch(categories, &block)
      return categories.find_in_batches(batch_size: BATCH_SIZE, &block) if categories.respond_to?(:find_in_batches)

      Array(categories).each_slice(BATCH_SIZE, &block)
    end

    def translate_batch(batch)
      categories = Array(batch)
      payload = JSON.parse(complete(categories).fetch(:content).to_s)
      apply_translations(categories, payload)
    rescue JSON::ParserError => e
      mark_batch_error(categories, "AI translation JSON parse error: #{e.message}")
    rescue StandardError => e
      mark_batch_error(categories, "AI translation error: #{e.class}: #{e.message}")
    end

    def complete(categories)
      definition = Agent.definition_for!("page_translation")
      client.complete(
        model: definition.fetch(:default_model_id),
        temperature: definition.fetch(:default_temperature),
        thinking_enabled: false,
        system_prompt: SYSTEM_PROMPT,
        context: "",
        messages: [
          {
            role: "user",
            content: {
              categories: categories.map { |category| serialize_category(category) }
            }.to_json
          }
        ],
        tools: []
      )
    end

    def serialize_category(category)
      {
        id: category.id,
        source: category.source,
        source_type: category.source_type,
        origin_language: category.origin_language,
        origin_name: category.origin_name
      }
    end

    def apply_translations(categories, payload)
      payload_items = translation_items(categories, payload)
      categories_by_id = categories.index_by(&:id)

      payload_items.each do |item|
        category = categories_by_id[item["id"].to_i]
        next unless category

        attrs = translation_attrs(category, item)
        attrs[:translated_at] = Time.current if attrs.any?
        attrs[:translation_error] = nil if attrs.any?
        category.update!(attrs) if attrs.any?
      end
    end

    def translation_items(categories, payload)
      return payload["categories"] if payload.is_a?(Hash) && payload["categories"].is_a?(Array)
      return payload if payload.is_a?(Array)
      return [payload.merge("id" => categories.first.id)] if categories.one? && payload.is_a?(Hash)

      raise ArgumentError, "AI translation response must include categories array"
    end

    def mark_batch_error(categories, message)
      categories.each { |category| category.update!(translation_error: message) }
    end

    def translation_attrs(category, payload)
      {
        name_cn: payload["name_cn"],
        name_en: payload["name_en"],
        name_ru: payload["name_ru"]
      }.each_with_object({}) do |(attr, value), attrs|
        next if category.public_send(attr).present?
        next if value.blank?

        attrs[attr] = value.to_s
      end
    end
  end
end
