module Api
  class ProfilesController < BaseController
    def show
      render json: { success: true, data: profile_json(current_user) }
    end

    def update
      current_user.assign_attributes(profile_params)

      if password_change?
        unless current_user.valid_password?(params[:current_password])
          current_user.errors.add(:current_password, :invalid)
          render_validation_errors
          return
        end

        if params[:password_confirmation].blank?
          current_user.errors.add(:password_confirmation, :blank)
          render_validation_errors
          return
        end

        current_user.assign_attributes(password_params)
      end

      current_user.avatar.attach(params[:avatar]) if params[:avatar].present?

      if current_user.save
        render json: { success: true, data: profile_json(current_user) }
      else
        render_validation_errors
      end
    end

    private

    def profile_params
      params.permit(:name, :email, :time_zone)
    end

    def password_params
      params.permit(:password, :password_confirmation)
    end

    def password_change?
      params[:password].present?
    end

    def render_validation_errors
      render json: { success: false, errors: current_user.errors.to_hash(true) }, status: :unprocessable_entity
    end
  end
end
