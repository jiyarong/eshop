require "test_helper"

module RawOzon
  class ListingImportJobTest < ActiveJob::TestCase
    class FakeListingClient
      attr_reader :imports

      def initialize(import_response:, info_response:)
        @import_response = import_response
        @info_response = info_response
        @imports = []
      end

      def import_products(items, request_id: nil)
        @imports << [items, request_id]
        @import_response
      end

      def import_info(_task_id)
        { "status" => "imported", "items" => [{ "product_id" => 12345 }] }
      end

      def product_info_list(product_ids:)
        @product_ids = product_ids
        @info_response
      end
    end

    setup do
      @token = SecureRandom.hex(4).upcase
      @sku = Ec::Sku.create!(sku_code: "JOB-#{@token}", product_name: "Job widget")
      @account = RawOzon::SellerAccount.create!(client_id: "job-#{@token}", api_key: "secret", company_type: "general")
      @store = Ec::Store.create!(platform: "ozon", store_name: "Job Ozon #{@token}", company_type: "general", ozon_raw_account_id: @account.id)
      @publication = Ec::OzonListingPublication.create!(
        account: @account, store: @store, sku_code: @sku.sku_code,
        operation: "import", offer_id: @sku.sku_code,
        payload: { "offer_id" => @sku.sku_code, "name" => "Job widget" },
        payload_checksum: Ec::OzonListingPublication.checksum_for({ "offer_id" => @sku.sku_code, "name" => "Job widget" })
      )
      @publication.confirm!
    end

    teardown do
      Ec::OzonListingPublication.where(id: @publication&.id).delete_all
      Ec::SkuProduct.where(sku_code: @sku&.sku_code).delete_all
      Ec::Sku.where(id: @sku&.id).delete_all
      Ec::Store.where(id: @store&.id).delete_all
      RawOzon::ProductAttribute.where(account_id: @account&.id).delete_all
      RawOzon::Product.where(account_id: @account&.id).delete_all
      RawOzon::SellerAccount.where(id: @account&.id).delete_all
    end

    test "submits a confirmed draft and binds the product after read-back" do
      fake = FakeListingClient.new(
        import_response: { "task_id" => "task-#{@token}" },
        info_response: { "items" => [{ "id" => 12345, "sku" => "98765", "offer_id" => @sku.sku_code, "name" => "Job widget" }] }
      )

      with_listing_client(fake) do
        RawOzon::ListingImportJob.perform_now(@publication.id)
        RawOzon::ListingImportPollJob.perform_now(@publication.id)
      end

      @publication.reload
      assert_equal "ready_for_price_stock", @publication.state
      assert_equal "task-#{@token}", @publication.ozon_task_id
      binding = Ec::SkuProduct.find_by!(store_id: @store.id, product_id: "12345")
      assert_equal @sku.sku_code, binding.sku_code
      assert_equal "98765", binding.platform_sku_id
      assert_equal [@sku.sku_code], fake.imports.first.first.map { |item| item["offer_id"] || item[:offer_id] }
    end

    test "does not submit an unconfirmed draft" do
      @publication.update!(state: :draft)
      fake = FakeListingClient.new(import_response: { "task_id" => "never" }, info_response: {})
      with_listing_client(fake) do
        RawOzon::ListingImportJob.perform_now(@publication.id)
      end

      assert_empty fake.imports
      assert_equal "draft", @publication.reload.state
    end

    private

    def with_listing_client(fake)
      singleton = RawOzon::ListingClient.singleton_class
      original = RawOzon::ListingClient.method(:for_account)
      singleton.define_method(:for_account) { |_account| fake }
      yield
    ensure
      singleton.define_method(:for_account, original)
    end
  end
end
