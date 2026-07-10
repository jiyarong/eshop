class UserAccessToken < ApplicationRecord
  TOKEN_PREFIX = "api_".freeze

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { joins(:user).where(users: { active: true }) }

  def self.generate_for!(user)
    raw_token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    access_token = create!(user: user, token_digest: digest(raw_token))

    [ raw_token, access_token ]
  end

  def self.authenticate(raw_token)
    return if raw_token.blank?

    access_token = active.find_by(token_digest: digest(raw_token))
    access_token&.update_column(:last_used_at, Time.current)
    access_token
  end

  def self.digest(raw_token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, raw_token.to_s)
  end
end
