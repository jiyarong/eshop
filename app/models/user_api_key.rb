class UserApiKey < ApplicationRecord
  MCP_ENDPOINT_URL = "https://eshop.evexport.cn/mcp".freeze
  TOKEN_PREFIX = "mcp_".freeze

  belongs_to :user

  validates :name, :token_digest, presence: true
  validates :token_digest, uniqueness: true
  validates :name, uniqueness: { scope: :user_id }

  scope :active, -> { where(revoked_at: nil).joins(:user).where(users: { active: true }) }

  def self.generate_for!(user, name:)
    raw_token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    api_key = create!(
      user: user,
      name: name,
      token_digest: digest(raw_token),
      encrypted_token: encrypt(raw_token)
    )

    [raw_token, api_key]
  end

  def self.authenticate(raw_token)
    return if raw_token.blank?

    api_key = active.find_by(token_digest: digest(raw_token))
    return unless api_key

    api_key.update_column(:last_used_at, Time.current)
    api_key.user
  end

  def self.digest(raw_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_token.to_s)
  end

  def self.encrypt(raw_token)
    encryptor.encrypt_and_sign(raw_token)
  end

  def self.decrypt(encrypted_token)
    return if encrypted_token.blank?

    encryptor.decrypt_and_verify(encrypted_token)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def self.encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
      .generate_key("user-api-key-token", ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def self.truncate_raw_token(raw_token)
    token = raw_token.to_s
    return "" if token.blank?
    return token if token.length <= 18

    "#{token.first(10)}…#{token.last(6)}"
  end

  def raw_token
    self.class.decrypt(encrypted_token)
  end

  def truncated_token
    self.class.truncate_raw_token(raw_token)
  end

  def mcp_server_config_json
    token = raw_token
    return "" if token.blank?

    JSON.pretty_generate(
      {
        mcpServers: {
          eshop_manage: {
            url: MCP_ENDPOINT_URL,
            headers: {
              Authorization: "Bearer #{token}"
            }
          }
        }
      }
    )
  end

  def self.mcp_server_config_json_for(raw_token)
    return "" if raw_token.blank?

    JSON.pretty_generate(
      {
        mcpServers: {
          eshop_manage: {
            url: MCP_ENDPOINT_URL,
            headers: {
              Authorization: "Bearer #{raw_token}"
            }
          }
        }
      }
    )
  end
end
