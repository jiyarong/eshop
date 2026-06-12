require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4)
  end

  teardown do
    User.where("email LIKE ?", "user-time-zone-#{@token}%").delete_all
  end

  test "defaults profile time zone to shanghai" do
    user = User.create!(
      email: "user-time-zone-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    assert_equal "Asia/Shanghai", user.time_zone
  end

  test "validates profile time zone against supported options" do
    user = User.new(
      email: "user-time-zone-#{@token}@example.com",
      password: "password123",
      password_confirmation: "password123",
      time_zone: "Mars/Phobos"
    )

    assert_not user.valid?
    assert_includes user.errors[:time_zone], "不在可选范围内"
  end
end
