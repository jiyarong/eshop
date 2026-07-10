class Sub2UserApiKeyProvisioner
  class Error < StandardError; end

  def self.call(user:, service: Sub2AIService.new)
    new(user:, service:).call
  end

  def initialize(user:, service:)
    @user = user
    @service = service
  end

  def call
    access_token = value_from(@service.login, "access_token", "token")
    name = "eshop-user-#{@user.id}"
    response = @service.create_api_key(access_token:, name:)
    key_data = nested_key_data(response)

    Sub2UserApiKey.create!(
      user: @user,
      remote_key_id: value_from(key_data, "id", "key_id", "api_key_id"),
      encrypted_api_key: Sub2UserApiKey.encrypt(value_from(key_data, "key", "api_key", "token")),
      name: key_data["name"].presence || key_data[:name].presence || name
    )
  rescue Sub2AIService::Error, KeyError, ActiveRecord::RecordInvalid => error
    raise Error, error.message
  end

  private

  def nested_key_data(response)
    raise KeyError, "Sub2 API key response is invalid" unless response.is_a?(Hash)

    nested = response["api_key"] || response[:api_key] || response["key"] || response[:key]
    nested.is_a?(Hash) ? nested : response
  end

  def value_from(data, *keys)
    raise KeyError, "Sub2 response is invalid" unless data.is_a?(Hash)

    value = keys.lazy.map { |key| data[key].presence || data[key.to_sym].presence }.find(&:present?)
    value || raise(KeyError, "Sub2 response is missing #{keys.first}")
  end
end
