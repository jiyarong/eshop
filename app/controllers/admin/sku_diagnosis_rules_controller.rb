module Admin
  class SkuDiagnosisRulesController < BaseController
    before_action :set_rule, only: %i[show edit update destroy]

    def index
      @rules = Ec::SkuDiagnosisRule.order(:id)
    end

    def new
      @rule = Ec::SkuDiagnosisRule.new(
        frequency: "daily",
        enabled: true,
        configuration: { "context_keys" => Ec::SkuDiagnosisRule::CONTEXT_KEYS }
      )
    end

    def create
      @rule = Ec::SkuDiagnosisRule.new(rule_params)
      if @rule.save
        redirect_to admin_sku_diagnosis_rules_path, notice: t("admin.sku_diagnosis_rules.notices.created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def show
    end

    def edit
    end

    def update
      if @rule.update(rule_params)
        redirect_to admin_sku_diagnosis_rules_path, notice: t("admin.sku_diagnosis_rules.notices.updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @rule.destroy!
      redirect_to admin_sku_diagnosis_rules_path, notice: t("admin.sku_diagnosis_rules.notices.deleted"), status: :see_other
    end

    private

    def set_rule
      @rule = Ec::SkuDiagnosisRule.find(params[:id])
    end

    def rule_params
      permitted = params.require(:ec_sku_diagnosis_rule).permit(
        :name, :prompt, :frequency, :enabled, :allowed_event_types_text, context_keys: [],
        execution_conditions: { grade: [], stage: [] }
      )
      permitted[:context_keys] = Array(permitted[:context_keys]).reject(&:blank?)
      conditions = permitted[:execution_conditions] || {}
      permitted[:execution_conditions] = {
        grade: Array(conditions[:grade]).reject(&:blank?),
        stage: Array(conditions[:stage]).reject(&:blank?)
      }
      permitted
    end
  end
end
