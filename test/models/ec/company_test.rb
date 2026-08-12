require "test_helper"

class Ec::CompanyTest < ActiveSupport::TestCase
  setup do
    @token = SecureRandom.hex(4).upcase
  end

  teardown do
    Ec::SkuBatch.where(supplier_id: companies.select(:id)).update_all(supplier_id: nil)
    Ec::Company.where(id: companies.select(:id)).delete_all
  end

  test "supplier is a company tag and supplier compatibility scope only returns tagged companies" do
    supplier = Ec::Supplier.create!(name: "Supplier #{@token}")
    broker = Ec::Company.create!(name: "Broker #{@token}", tags: [ "customs_broker" ])

    assert supplier.supplier?
    assert_includes Ec::Company.tagged("customs_broker"), broker
    assert_includes Ec::Supplier.all, supplier
    assert_not_includes Ec::Supplier.all, broker
  end

  test "normalizes supplier grade and validates online company URL" do
    company = Ec::Company.new(name: "Online #{@token}", tags: [ "supplier" ], channel: "online", supplier_grade: "a")

    assert_not company.valid?
    assert_predicate company.errors[:online_url], :present?

    company.online_url = "https://example.com/supplier"
    assert company.save
    assert_equal "A", company.supplier_grade
  end

  test "offline company clears an obsolete online URL" do
    company = Ec::Company.create!(
      name: "Offline #{@token}", tags: [ "supplier" ], channel: "offline",
      online_url: "https://example.com/old"
    )

    assert_nil company.online_url
  end

  test "online company URL must use HTTP or HTTPS" do
    company = Ec::Company.new(
      name: "Unsafe URL #{@token}", tags: [ "supplier" ],
      channel: "online", online_url: "javascript:alert(1)"
    )

    assert_not company.valid?
    assert_predicate company.errors[:online_url], :present?
  end

  test "rejects unsupported company tags" do
    company = Ec::Company.new(name: "Unknown tag #{@token}", tags: [ "unknown" ])

    assert_not company.valid?
    assert_predicate company.errors[:tags], :present?
  end

  private

  def companies
    Ec::Company.where("name LIKE ?", "%#{@token}%")
  end
end
