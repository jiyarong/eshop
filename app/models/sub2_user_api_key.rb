class Sub2UserApiKey < ApplicationRecord
  ENCRYPTION_SALT = "sub2-user-api-key".freeze

  belongs_to :user

  validates :user_id, uniqueness: true
  validates :remote_key_id, :encrypted_api_key, :name, presence: true
  validates :remote_key_id, uniqueness: true

  def self.encrypt(raw_api_key)
    encryptor.encrypt_and_sign(raw_api_key)
  end

  def self.decrypt(encrypted_api_key)
    encryptor.decrypt_and_verify(encrypted_api_key)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def self.encryptor
    key = ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base)
      .generate_key(ENCRYPTION_SALT, ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  def api_key
    self.class.decrypt(encrypted_api_key)
  end

  def masked_api_key
    key = api_key.to_s
    return "" if key.blank?
    return key if key.length <= 12

    "#{key.first(6)}...#{key.last(4)}"
  end
end
