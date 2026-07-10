module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :edit, :update, :create_api_key, :revoke_api_key]
    before_action :load_roles, only: [:new, :edit, :create, :update]

    def index
      @users = User.includes(:roles).order(:email)
    end

    def show
    end

    def new
      @user = User.new(active: true)
    end

    def edit
    end

    def create
      @user = User.new(user_params)
      assign_roles(@user)

      if save_user_with_sub2_key
        redirect_to admin_user_path(@user)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      attrs.delete(:password_confirmation) if attrs[:password_confirmation].blank?
      @user.assign_attributes(attrs)
      assign_roles(@user)

      if @user.save
        redirect_to admin_user_path(@user)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def create_api_key
      raw_token, = UserApiKey.generate_for!(@user, name: api_key_name)

      redirect_to admin_user_path(@user), notice: t("admin.users.api_keys.created", token: raw_token)
    end

    def revoke_api_key
      api_key = @user.api_keys.find(params[:api_key_id])
      api_key.update!(revoked_at: Time.current)

      redirect_to admin_user_path(@user), notice: t("admin.users.api_keys.revoked")
    end

    private

    def set_user
      @user = User.includes(:roles).find(params[:id])
    end

    def load_roles
      @roles = Role.order(:position, :code)
    end

    def user_params
      params.require(:user).permit(:name, :email, :password, :password_confirmation, :active)
    end

    def api_key_name
      params.fetch(:api_key, {}).permit(:name)[:name].presence || "MCP"
    end

    def role_ids
      params.require(:user).permit(role_ids: [])[:role_ids].to_a.reject(&:blank?)
    end

    def assign_roles(user)
      user.roles = Role.where(id: role_ids)
    end

    def save_user_with_sub2_key
      return false unless @user.valid?

      User.transaction do
        @user.save!
        Sub2UserApiKeyProvisioner.call(user: @user)
      end
      true
    rescue Sub2UserApiKeyProvisioner::Error => error
      Rails.logger.error("Sub2 API key provisioning failed for #{@user.email}: #{error.message}")
      @user.errors.add(:base, t("admin.users.errors.sub2_api_key_creation_failed"))
      false
    end
  end
end
