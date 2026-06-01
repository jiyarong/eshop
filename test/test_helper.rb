ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Role.seed_defaults! if defined?(Role)
  end
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def create_user_with_roles(email, *role_codes)
    user = User.create!(email: email, password: "password123", password_confirmation: "password123")
    role_codes.each { |code| user.roles << Role.find_by!(code: code) }
    user
  end
end
