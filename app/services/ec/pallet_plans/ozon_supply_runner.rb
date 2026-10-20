module Ec
  module PalletPlans
    class OzonSupplyRunner
      MAX_POLLS = 60

      def initialize(submission:, client: nil, sync: nil)
        @submission = submission
        @plan = submission.pallet_plan
        @account = @plan.store.raw_ozon_account
        @client = client
        @sync = sync
      end

      def call
        SyncRunLock.with_lock(@submission.lock_name, wait: false) do
          @submission.reload
          return @submission unless @submission.running?
          @stage = @submission.state
          begin
            raise Error.new(:invalid_store) unless @account&.is_active? && @plan.store.is_active?
            @client ||= RawOzon::SupplyClient.new(account: @account)
            case @stage
            when "queued" then create_draft
            when "draft_submitting" then fail_submission(:write_uncertain, review: true)
            when "calculating" then calculate_draft
            when "loading_timeslots" then load_timeslots
            when "order_queued" then create_order
            when "order_submitting" then advance("creating")
            when "creating" then read_order
            when "syncing" then sync_order
            when "cargoes" then sync_cargoes
            when "finalizing" then finalize
            end
          rescue StandardError => error
            handle_error(error)
          end
        end
        @submission
      end

      private

      def data
        @submission.data
      end

      def advance(state, extra = {})
        @submission.update!(state: state, poll_attempts: 0, last_error: nil, data: data.merge(extra))
      end

      def pending!
        attempts = @submission.poll_attempts + 1
        @submission.update!(poll_attempts: attempts)
        fail_submission(:poll_timeout) if attempts >= MAX_POLLS
      end

      def fail_submission(key, review: false, message: nil)
        @submission.update!(state: review ? "review_required" : "failed",
          last_error: message || Error.new(key).message, data: data.merge("resume_state" => @stage))
      end

      def validate_response!(response)
        errors = response["errors"].presence || response["error_reasons"].presence
        reason = response["error_reason"]
        errors ||= reason if reason.present? && reason != "UNSPECIFIED"
        raise Error.new(:platform_rejected, reason: errors.to_json.truncate(1800)) if error_present?(errors)
      end

      def error_present?(value)
        case value
        when Hash then value.values.any? { |entry| error_present?(entry) }
        when Array then value.any? { |entry| error_present?(entry) }
        else value.present?
        end
      end

      def positive_id!(value)
        raise Error.new(:invalid_platform_response) unless value.to_s.match?(/\A[1-9]\d*\z/)
        value.to_s
      end

      def create_draft
        authorize_write!
        items = @plan.items.map { |item| { sku: positive_id!(item.platform_sku_id).to_i, quantity: item.units } }
        advance("draft_submitting")
        response = @client.create_draft(type: data.fetch("supply_type"), cluster_id: @plan.macrolocal_cluster_id,
          items: items, drop_off: data["drop_off"])
        validate_response!(response)
        draft_id = positive_id!(response["draft_id"])
        @submission.update!(draft_id: draft_id)
        advance("calculating", "draft_created_at" => Time.current.iso8601)
      end

      def calculate_draft
        response = @client.draft_info(@submission.draft_id)
        validate_response!(response)
        return pending! if response["status"] == "IN_PROGRESS"
        raise Error.new(:invalid_platform_response) unless response["status"] == "SUCCESS"
        cluster = Array(response["clusters"]).find do |row|
          row["macrolocal_cluster_id"].to_s == @plan.macrolocal_cluster_id.to_s && row["supply_type"] == data.fetch("supply_type")
        end
        warehouses = Array(cluster&.fetch("warehouses", [])).select do |row|
          row.dig("availability_status", "state") == "FULL_AVAILABLE" && row.dig("storage_warehouse", "warehouse_id").present? && row["bundle_id"].present?
        end
        raise Error.new(:no_available_warehouse) if warehouses.empty?
        advance("warehouse_required", "warehouses" => warehouses)
      end

      def selection
        [{ macrolocal_cluster_id: @plan.macrolocal_cluster_id,
          storage_warehouse_id: data.fetch("warehouse").fetch("storage_warehouse").fetch("warehouse_id").to_i }]
      end

      def load_timeslots
        raise Error.new(:draft_expired) if @submission.draft_expired?
        today = Time.current.in_time_zone(@plan.time_zone).to_date
        response = @client.timeslots(draft_id: @submission.draft_id.to_i, supply_type: data.fetch("supply_type"),
          selected_cluster_warehouses: selection, date_from: today.iso8601, date_to: (today + 27).iso8601)
        validate_response!(response)
        calendar = response.dig("result", "drop_off_warehouse_timeslots").to_h
        slots = Array(calendar["days"]).flat_map { |day| Array(day["timeslots"]) }
          .select { |slot| slot["from_in_timezone"].present? && slot["to_in_timezone"].present? }
        raise Error.new(:no_timeslots) if slots.empty?
        advance("timeslot_required", "timeslots" => slots, "warehouse_timezone" => calendar["warehouse_timezone"])
      end

      def create_order
        authorize_write!
        raise Error.new(:draft_expired) if @submission.draft_expired?
        validate_selected_bundle!
        advance("order_submitting", "order_attempted" => true)
        response = @client.create_supply(draft_id: @submission.draft_id.to_i, supply_type: data.fetch("supply_type"),
          selected_cluster_warehouses: selection, timeslot: data.fetch("timeslot"))
        # A retry after a lost response must query this draft, never create a new order.
        advance("creating", "create_response" => response)
      end

      def validate_selected_bundle!
        response = @client.draft_info(@submission.draft_id)
        validate_response!(response)
        raise Error.new(:invalid_platform_response) unless response["status"] == "SUCCESS"
        cluster = Array(response["clusters"]).find { |row| row["macrolocal_cluster_id"].to_s == @plan.macrolocal_cluster_id.to_s && row["supply_type"] == data.fetch("supply_type") }
        warehouse = Array(cluster&.fetch("warehouses", [])).find do |row|
          row.dig("storage_warehouse", "warehouse_id").to_s == data.dig("warehouse", "storage_warehouse", "warehouse_id").to_s && row.dig("availability_status", "state") == "FULL_AVAILABLE"
        end
        raise Error.new(:no_available_warehouse) unless warehouse && warehouse["bundle_id"].present?
        items = @client.bundle_items(warehouse.fetch("bundle_id"))
        expected = @plan.items.each_with_object(Hash.new(0)) { |item, totals| totals[item.platform_sku_id.to_s] += item.units }
        actual = items.each_with_object(Hash.new(0)) { |item, totals| totals[item["sku"].to_s] += item["quantity"].to_i }
        raise Error.new(:supply_mismatch) unless expected == actual
        by_sku = items.index_by { |item| item["sku"].to_s }
        raise Error.new(:supply_mismatch) unless by_sku.size == items.size
        @plan.pallets.includes(items: :pallet_plan_item).each do |pallet|
          pallet.items.each do |item|
            source = by_sku.fetch(item.pallet_plan_item.platform_sku_id.to_s)
            raise Error.new(:missing_cargo_metadata, sku: item.pallet_plan_item.sku_code) unless source["barcode"].present? && source["quant"].to_i.positive? && item.units % source["quant"].to_i == 0
          end
        end
      end

      def read_order
        response = @client.supply_status(@submission.draft_id)
        return pending! if response["status"] == "IN_PROGRESS"
        if response["status"] == "FAILED"
          if response["order_id"].to_s.match?(/\A[1-9]\d*\z/)
            @submission.update!(order_id: response["order_id"].to_s)
            return fail_submission(:write_uncertain, review: true)
          end
          @submission.update!(data: data.merge("order_failed" => true))
        end
        validate_response!(response)
        raise Error.new(:invalid_platform_response) unless response["status"] == "SUCCESS"
        @submission.update!(order_id: positive_id!(response["order_id"]), data: data.merge("order_failed" => false))
        advance("syncing")
      end

      def refresh_order
        (@sync || RawOzon::DailySync.new(@account, days: 2)).sync_supply_orders(order_ids: [@submission.order_id])
        OzonReconciler.new(plan: @plan.reload).bind!(@submission.order_id, enqueue: false)
        raise Error.new(:supply_pending) if @plan.reload.ozon_order_id.blank? || @plan.sync_error.present?
        warehouse_id = data.fetch("warehouse").fetch("storage_warehouse").fetch("warehouse_id").to_s
        raise Error.new(:supply_warehouse_changed) if @plan.pallets.any? { |pallet| pallet.storage_warehouse_id.to_s != warehouse_id }
      end

      def sync_order
        refresh_order
        advance("cargoes", "cargo_operations" => {})
      end

      def cargo_payloads
        order = RawOzon::SupplyOrder.find_by!(account_id: @account.id, supply_order_id: @submission.order_id)
        metadata = order.supply_order_items.to_a.index_by { |item| [item.ozon_supply_id.to_s, item.platform_sku_id.to_s] }
        @plan.pallets.includes(items: :pallet_plan_item).group_by(&:ozon_supply_id).to_h do |supply_id, pallets|
          positive_id!(supply_id)
          cargoes = pallets.map do |pallet|
            items = pallet.items.map do |item|
              plan_item = item.pallet_plan_item
              source = metadata.fetch([supply_id, plan_item.platform_sku_id.to_s]).raw_json.to_h
              # quant is the platform's bundle quantum, not the number of pieces in our shipping carton.
              quant = source["quant"].to_i
              raise Error.new(:missing_cargo_metadata, sku: plan_item.sku_code) unless source["barcode"].present? && quant.positive? && item.units % quant == 0
              { barcode: source["barcode"], offer_id: source["offer_id"], quant: quant, quantity: item.units }.compact
            end
            { key: "#{@plan.plan_no}-#{pallet.position}", value: { type: "PALLET", items: items } }
          end
          [supply_id, cargoes]
        end
      end

      def sync_cargoes
        operations = data.fetch("cargo_operations").deep_dup
        payloads = cargo_payloads
        supply_id, cargoes = payloads.find { |id, _| operations.dig(id, "status") != "SUCCESS" }
        return advance("finalizing") unless supply_id
        operation = operations[supply_id]
        if operation.nil?
          authorize_write!
          operations[supply_id] = { "status" => "SUBMITTING" }
          @submission.update!(data: data.merge("cargo_operations" => operations))
          response = @client.create_cargoes(supply_id: supply_id, cargoes: cargoes)
          validate_response!(response)
          raise Error.new(:invalid_platform_response) if response["operation_id"].blank?
          operations[supply_id] = { "operation_id" => response["operation_id"], "status" => "IN_PROGRESS" }
        elsif operation["status"] == "SUBMITTING"
          return fail_submission(:write_uncertain, review: true)
        else
          response = @client.cargoes_info(operation.fetch("operation_id"))
          validate_response!(response)
          return pending! if response["status"] == "IN_PROGRESS"
          raise Error.new(:invalid_platform_response) unless response["status"] == "SUCCESS"
          rows = Array(response.dig("result", "cargoes"))
          raise Error.new(:invalid_platform_response) unless rows.size == cargoes.size
          cargo_ids = rows.to_h { |row| [row["key"], positive_id!(row.dig("value", "cargo_id"))] }
          raise Error.new(:invalid_platform_response) unless cargo_ids.keys.sort == cargoes.map { |row| row[:key] }.sort && cargo_ids.values.uniq.size == cargoes.size
          @plan.pallets.where(ozon_supply_id: supply_id).each do |pallet|
            pallet.update!(ozon_cargo_id: cargo_ids.fetch("#{@plan.plan_no}-#{pallet.position}"))
          end
          operations[supply_id] = operation.merge("status" => "SUCCESS", "cargoes" => cargo_ids)
        end
        advance("cargoes", "cargo_operations" => operations)
      end

      def finalize
        ids = @plan.pallets.reorder(nil).distinct.pluck(:ozon_supply_id)
        response = @client.cargoes_rules(ids)
        validate_response!(response)
        lists = Array(response["supply_check_lists"])
        raise Error.new(:cargo_rules_failed) unless lists.map { |row| row["supply_id"].to_s }.sort == ids.sort
        valid = lists.all? do |list|
          list["cargoes_presents_rule"].to_h["satisfied"] == true && list["is_valid_distribution_rule"].to_h["satisfied"] == true &&
            list.all? { |_key, rule| !rule.is_a?(Hash) || rule["is_applicable"] == false || rule["is_required"] == false || rule["satisfied"] == true }
        end
        @submission.update!(data: data.merge("cargo_rules" => response))
        raise Error.new(:cargo_rules_failed) unless valid
        refresh_order
        advance("completed", "completed_at" => Time.current.iso8601)
      end

      def authorize_write!
        @plan.reload
        user = data["requested_by_id"].present? ? User.find_by(id: data["requested_by_id"]) : @plan.created_by
        raise Error.new(:sku_unavailable) unless user&.can?(:manage_skus)
        raise Error.new(:sku_unavailable) if @plan.items.where.not(sku_code: WeeklyProfitReports::AccessScope.new(user).visible_skus.select(:sku_code)).exists?
        raise Error.new(:invalid_status) unless @plan.status.in?(Ec::PalletPlan::EDITABLE_STATUSES)
      end

      def handle_error(error)
        # An unknown write result cannot be retried safely. Supply creation is the
        # exception: its durable draft ID allows polling without another write.
        if @submission.state == "order_submitting"
          advance("creating")
        else
          uncertain = @submission.state == "draft_submitting" && !error.is_a?(Error) ||
            data.fetch("cargo_operations", {}).values.any? { |operation| operation["status"] == "SUBMITTING" }
          message = if uncertain
            Error.new(:write_uncertain).message
          elsif error.is_a?(Error) || error.is_a?(RawOzon::OzonClient::ApiError)
            error.message
          else
            Rails.logger.error("Ozon supply submission #{@submission.id} failed at #{@stage}: #{error.class}")
            Error.new(:sync_failed).message
          end
          fail_submission(:sync_failed, review: uncertain, message: message)
        end
      end
    end
  end
end
