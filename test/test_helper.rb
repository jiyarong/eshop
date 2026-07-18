ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    Role.seed_defaults! if defined?(Role)
  end

  def gbrain_page_attributes(slug:, **overrides)
    {
      slug: slug,
      title: "Ozon RU knowledge",
      page_type: "note",
      subtype: "research-note",
      aliases: [ "Ozon knowledge" ],
      tags: %w[platform/ozon country/ru status/current],
      platform: "ozon",
      country: "RU",
      region_scope: [],
      category_scope: [],
      reviewed_at: Date.current,
      review_after: 3.months.from_now.to_date,
      source_tier: "team-validated",
      confidence: "medium",
      summary: "Use the documented rule within its stated scope.",
      content: "## Core strategy\n\nDocumented body.",
      content_updated_at: Time.current
    }.merge(overrides)
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
