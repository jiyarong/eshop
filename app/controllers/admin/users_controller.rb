module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :edit, :update]
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
      if @user.save
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

    private

    def set_user
      @user = User.includes(:roles).find(params[:id])
    end

    def load_roles
      @roles = Role.order(:position, :code)
    end

    def user_params
      params.require(:user).permit(:email, :password, :password_confirmation, :active)
    end

    def role_ids
      params.require(:user).permit(role_ids: [])[:role_ids].to_a.reject(&:blank?)
    end

    def assign_roles(user)
      user.roles = Role.where(id: role_ids)
    end
  end
end
